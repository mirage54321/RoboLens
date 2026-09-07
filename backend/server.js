// https://frc-events.firstinspires.org/2026/allteams
const express = require('express');
const cors = require('cors');
const fetch = require('node-fetch');
const webpush = require('web-push');
const { MongoClient } = require('mongodb');
const FIRST_USERNAME = process.env.FIRST_USERNAME;
const FIRST_TOKEN = process.env.FIRST_TOKEN;
const app = express();

const PORT = process.env.PORT || 3000;
const MONGODB_URI = process.env.MONGODB_URI;
const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const DB_NAME = process.env.DB_NAME || 'ridgebotics';
const FRONTEND_ORIGIN = process.env.FRONTEND_ORIGIN || '*';

const GEMINI_SCAN_URL =
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';
const GEMINI_TEXT_URL =
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent';


const GEMINI_MAX_CONCURRENT = Number(process.env.GEMINI_MAX_CONCURRENT || 2);
const GEMINI_MAX_RETRIES = Number(process.env.GEMINI_MAX_RETRIES || 3);
const GEMINI_BASE_DELAY_MS = Number(process.env.GEMINI_BASE_DELAY_MS || 2000);

let geminiActiveCount = 0;
const geminiWaitQueue = [];

function acquireGeminiSlot() {
  if (geminiActiveCount < GEMINI_MAX_CONCURRENT) {
    geminiActiveCount++;
    return Promise.resolve();
  }
  return new Promise((resolve) => geminiWaitQueue.push(resolve));
}

function releaseGeminiSlot() {
  const next = geminiWaitQueue.shift();
  if (next) {
    next();
  } else {
    geminiActiveCount--;
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isRetryableGeminiStatus(status) {
  // 429 = rate limited 
  // 503 = model temporarily overloaded.
  return status === 429 || status === 503;
}

function retryDelayMsFromResponse(response, attempt) {
  const retryAfter = response.headers.get('retry-after');
  const parsed = Number(retryAfter);
  if (Number.isFinite(parsed) && parsed > 0) {
    return parsed * 1000;
  }
  return GEMINI_BASE_DELAY_MS * Math.pow(2, attempt); 
}

async function callGeminiWithRetry(url, body) {
  await acquireGeminiSlot();
  try {
    let lastResponse;
    let lastData;
    for (let attempt = 0; attempt < GEMINI_MAX_RETRIES; attempt++) {
      const response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      const data = await response.json();

      if (response.ok || !isRetryableGeminiStatus(response.status)) {
        return { status: response.status, data };
      }

      lastResponse = response;
      lastData = data;

      const isLastAttempt = attempt === GEMINI_MAX_RETRIES - 1;
      if (isLastAttempt) break;

      const delay = retryDelayMsFromResponse(response, attempt);
      console.warn(
        `Gemini ${response.status}, retrying in ${delay}ms (attempt ${attempt + 1}/${GEMINI_MAX_RETRIES})`,
      );
      await sleep(delay);
    }
    return { status: lastResponse.status, data: lastData };
  } finally {
    releaseGeminiSlot();
  }
}

const TBA_AUTH_KEY = process.env.TBA_AUTH_KEY;
const TBA_BASE = 'https://www.thebluealliance.com/api/v3';
const NOTIFY_WINDOW_MIN = 12;
const FINAL_SCORE_WINDOW_MIN = 180;


const NOTIFY_STAGES = [
  { stage: 'alliance', minMinutesAway: 15, maxMinutesAway: 20 },
  { stage: 'queue', minMinutesAway: 10, maxMinutesAway: 15 },
  { stage: 'matchup', minMinutesAway: 5, maxMinutesAway: 10 },
  { stage: 'field', minMinutesAway: 0, maxMinutesAway: 5 },
  { stage: 'start', minMinutesAway: -NOTIFY_WINDOW_MIN, maxMinutesAway: 0 },
];

function stageForMinutesAway(minsAway) {
  for (const { stage, minMinutesAway, maxMinutesAway } of NOTIFY_STAGES) {
    if (minsAway > minMinutesAway && minsAway <= maxMinutesAway) return stage;
  }
  return null;
}

function allianceOpr(oprMap, teamKeys) {
  return teamKeys.reduce((sum, key) => sum + (oprMap[key] || 0), 0);
}

function joinWithAnd(items) {
  if (items.length === 0) return '';
  if (items.length === 1) return items[0];
  return `${items.slice(0, -1).join(', ')} and ${items[items.length - 1]}`;
}


function allianceTeammates(match, teamKey) {
  const onRed = (match.alliances?.red?.team_keys || []).includes(teamKey);
  const list = onRed ? match.alliances?.red?.team_keys : match.alliances?.blue?.team_keys;
  return (list || []).filter((key) => key !== teamKey).map((key) => key.replace(/^frc/, ''));
}


function allianceSlotLabel(match, teamKey) {
  const onRed = (match.alliances?.red?.team_keys || []).includes(teamKey);
  const list = onRed ? match.alliances?.red?.team_keys : match.alliances?.blue?.team_keys;
  if (!list) return null;
  const idx = list.indexOf(teamKey);
  if (idx === -1) return null;
  return `${onRed ? 'Red' : 'Blue'} ${idx + 1}`;
}


function buildMatchupContext(match, teamKey, oprMap) {
  const onRed = (match.alliances?.red?.team_keys || []).includes(teamKey);
  const myAlliance = onRed ? match.alliances.red.team_keys : match.alliances.blue.team_keys;
  const oppAlliance = onRed ? match.alliances.blue.team_keys : match.alliances.red.team_keys;
  if (!myAlliance || !oppAlliance) return null;

  const myOpr = allianceOpr(oprMap, myAlliance);
  const oppOpr = allianceOpr(oprMap, oppAlliance);

  const hasOprData = Object.keys(oprMap).length > 0 && (myOpr !== 0 || oppOpr !== 0);
  const winProbPct = hasOprData
    ? Math.round(Math.min(0.99, Math.max(0.01, myOpr / (myOpr + oppOpr))) * 100)
    : null;

  let topOpponentKey = null;
  for (const key of oppAlliance) {
    if (key === teamKey) continue;
    if (topOpponentKey === null || (oprMap[key] || 0) > (oprMap[topOpponentKey] || 0)) {
      topOpponentKey = key;
    }
  }

  return {
    winProbPct,
    topOpponentNumber: topOpponentKey ? topOpponentKey.replace(/^frc/, '') : null,
  };
}

function finalScoreSummary(match, teamKey) {
  const onRed = (match.alliances?.red?.team_keys || []).includes(teamKey);
  const myScore = onRed ? match.alliances?.red?.score : match.alliances?.blue?.score;
  const oppScore = onRed ? match.alliances?.blue?.score : match.alliances?.red?.score;
  if (myScore == null || oppScore == null) return null;
  const teamNumber = teamKey.replace(/^frc/, '');
  const result = myScore > oppScore ? 'won' : myScore < oppScore ? 'lost' : 'tied';
  return `Team ${teamNumber} ${result} ${myScore}-${oppScore}.`;
}

function notificationForStage(teamNumber, label, stage, extra = {}) {
  switch (stage) {
    case 'alliance': {
      const teammates = (extra.teammates || []).map((n) => `Team ${n}`);
      return {
        title: `Team ${teamNumber}: ${label} in 20 min`,
        body: teammates.length
          ? `Your alliance this match: you + ${joinWithAnd(teammates)}.`
          : "Your match is coming up in 20 minutes. Alliance info isn't available yet.",
      };
    }
    case 'queue': {
      const slot = extra.slotLabel;
      return {
        title: `Team ${teamNumber}: ${label} in 15 min`,
        body: slot
          ? `You're on queue. You'll be ${slot} this match.`
          : "You're on queue. Head to the queuing line.",
      };
    }
    case 'matchup': {
      const { winProbPct, topOpponentNumber } = extra;
      const parts = [];
      if (winProbPct != null) parts.push(`You have about a ${winProbPct}% chance of winning this match.`);
      if (topOpponentNumber) parts.push(`Watch Team ${topOpponentNumber} on the other alliance. They're projected to contribute the most, so they're the one to defend.`);
      return {
        title: `Team ${teamNumber}: ${label} in 10 min`,
        body: parts.length ? parts.join(' ') : 'Your match is coming up in 10 minutes.',
      };
    }
    case 'field':
      return {
        title: `Team ${teamNumber}: ${label} in 5 min`,
        body: 'Be on the field. Your match starts in 5 minutes.',
      };
    case 'start':
      return {
        title: `Team ${teamNumber}: ${label} is starting`,
        body: 'Game starting now!',
      };
    case 'final':
      return {
        title: `Team ${teamNumber}: ${label} final score`,
        body: extra.summary || 'Your match has finished.',
      };
    default:
      return {
        title: `Team ${teamNumber}: ${label}`,
        body: 'Match update.',
      };
  }
}

const FAKE_TEAM_NUMBER = '-4388';
const FAKE_TEAM_KEY = `frc${FAKE_TEAM_NUMBER}`;
const FAKE_EVENT_KEY = 'faketest2026';

function isFakeTeamNumber(teamNumber) {
  return cleanString(teamNumber) === FAKE_TEAM_NUMBER;
}

const FAKE_DATE_TO_DAY_OFFSET = {
  '2026-08-24': 0,
  '2026-08-25': 1,
  '2026-08-26': 2,
};

const FAKE_FIXED_ANCHOR = new Date(Date.UTC(2026, 8, 7)); // 2026-09-07; = offset 0 (practice)

function fakeResolvedDate(oldDateStr) {
  const offset = FAKE_DATE_TO_DAY_OFFSET[oldDateStr];
  const d = new Date(FAKE_FIXED_ANCHOR);
  d.setUTCDate(d.getUTCDate() + offset);
  return d.toISOString().slice(0, 10);
}

function fakeEvent() {
  return {
    key: FAKE_EVENT_KEY,
    name: 'RoboLens Test Event \u2014 Pikes Peak Regional replay (fake, team -4388 only)',
    start_date: fakeResolvedDate('2026-08-24'),
    end_date: fakeResolvedDate('2026-08-26'),
    city: 'Colorado Springs',
    state_prov: 'CO',
    country: 'USA',
  };
}

function denverUtcOffsetHours(dateStr) {
  const [y, m, d] = dateStr.split('-').map(Number);
  const probe = new Date(Date.UTC(y, m - 1, d, 12));
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/Denver',
    timeZoneName: 'shortOffset',
  }).formatToParts(probe);
  const raw = parts.find((p) => p.type === 'timeZoneName')?.value || 'GMT-7';
  const match = raw.match(/GMT([+-]\d+)/);
  return match ? parseInt(match[1], 10) : -7;
}

function fakeMstEpochSeconds(dateStr, hour, minute) {
  const resolved = fakeResolvedDate(dateStr);
  const [y, m, d] = resolved.split('-').map(Number);
  const offsetHours = denverUtcOffsetHours(resolved);
  return Math.floor(Date.UTC(y, m - 1, d, hour, minute) / 1000) - offsetHours * 3600;
}

const FAKE_PRACTICE_SCHEDULE = [
  { num: 1, date: '2026-08-24', hour: 9, minute: 4, red: ['2945', '10333', '8044'], blue: ['1339', '662', '3807'] },
  { num: 2, date: '2026-08-24', hour: 9, minute: 19, red: ['2996', '4418', '1619'], blue: ['2240', '6358', '10114'] },
  { num: 3, date: '2026-08-24', hour: 9, minute: 31, red: ['4293', '1339', '9501'], blue: ['3648', '1977', '4499'] },
  { num: 4, date: '2026-08-24', hour: 9, minute: 42, red: ['4944', '8044', '2083'], blue: ['159', '4183', '9068'] },
  { num: 5, date: '2026-08-24', hour: 9, minute: 52, red: ['5493', '4499', '9134'], blue: ['9586', '7485', '-4388'] },
  { num: 6, date: '2026-08-24', hour: 10, minute: 4, red: ['4068', '4293', '1619'], blue: ['8044', '2240', '1977'] },
  { num: 7, date: '2026-08-24', hour: 10, minute: 16, red: ['498', '8334', '4499'], blue: ['11220', '2996', '159'] },
  { num: 8, date: '2026-08-24', hour: 10, minute: 27, red: ['7485', '9501', '4293'], blue: ['3807', '9586', '4550'] },
  { num: 9, date: '2026-08-24', hour: 10, minute: 39, red: ['662', '4499', '3648'], blue: ['498', '5493', '2996'] },
  { num: 10, date: '2026-08-24', hour: 10, minute: 50, red: ['-4388', '9068', '8044'], blue: ['2240', '4183', '4293'] },
  { num: 11, date: '2026-08-24', hour: 11, minute: 1, red: ['2945', '2083', '6358'], blue: ['4499', '10114', '4068'] },
  { num: 12, date: '2026-08-24', hour: 11, minute: 13, red: ['8334', '9586', '2996'], blue: ['4293', '2945', '4944'] },
  { num: 13, date: '2026-08-24', hour: 11, minute: 24, red: ['1977', '10333', '159'], blue: ['4293', '2945', '1619'] },
  { num: 14, date: '2026-08-24', hour: 11, minute: 36, red: ['498', '3648', '1339'], blue: ['1619', '2996', '4499'] },
  { num: 15, date: '2026-08-24', hour: 11, minute: 47, red: ['9586', '11220', '9501'], blue: ['2083', '9134', '662'] },
  { num: 16, date: '2026-08-24', hour: 11, minute: 57, red: ['10114', '4293', '1619'], blue: ['4550', '4068', '5493'] },
  { num: 17, date: '2026-08-24', hour: 12, minute: 6, red: ['6358', '498', '4499'], blue: ['9068', '3807', '2240'] },
  { num: 18, date: '2026-08-24', hour: 12, minute: 19, red: ['4944', '9134', '2945'], blue: ['9501', '1619', '4293'] },
  { num: 19, date: '2026-08-24', hour: 12, minute: 31, red: ['-4388', '2240', '10114'], blue: ['8044', '3648', '2996'] },
  { num: 20, date: '2026-08-24', hour: 12, minute: 41, red: ['3288', '1339', '7485'], blue: ['2083', '498', '1977'] },
  { num: 21, date: '2026-08-24', hour: 12, minute: 52, red: ['662', '159', '9586'], blue: ['-4388', '4068', '9068'] },
  { num: 22, date: '2026-08-24', hour: 13, minute: 4, red: ['3807', '4418', '5493'], blue: ['6358', '8334', '4183'] },
  { num: 23, date: '2026-08-24', hour: 13, minute: 12, red: ['10114', '2240', '4944'], blue: ['6358', '-4388', '498'] },
  { num: 24, date: '2026-08-24', hour: 13, minute: 22, red: ['9068', '7485', '11220'], blue: ['3648', '9501', '498'] },
  { num: 25, date: '2026-08-24', hour: 13, minute: 31, red: ['4499', '8044', '2083'], blue: ['2240', '4293', '4418'] },
  { num: 26, date: '2026-08-24', hour: 13, minute: 41, red: ['159', '4944', '8334'], blue: ['9586', '1339', '6358'] },
  { num: 27, date: '2026-08-24', hour: 13, minute: 53, red: ['4183', '1977', '4550'], blue: ['2996', '662', '2240'] },
  { num: 28, date: '2026-08-24', hour: 14, minute: 9, red: ['1619', '4499', '498'], blue: ['5493', '2083', '-4388'] },
  { num: 29, date: '2026-08-24', hour: 14, minute: 20, red: ['4068', '6358', '4293'], blue: ['9501', '3288', '9134'] },
  { num: 30, date: '2026-08-24', hour: 14, minute: 29, red: ['2240', '9068', '4499'], blue: ['1339', '4944', '2996'] },
  { num: 31, date: '2026-08-24', hour: 14, minute: 40, red: ['2240', '11220', '4293'], blue: ['4183', '4068', '7485'] },
  { num: 32, date: '2026-08-24', hour: 14, minute: 50, red: ['10333', '9068', '9586'], blue: ['1977', '5493', '10114'] },
  { num: 33, date: '2026-08-24', hour: 15, minute: 0, red: ['8044', '4499', '498'], blue: ['4550', '1619', '662'] },
];
 

const FAKE_QUALS_SCHEDULE = [
  { num: 1, date: '2026-08-25', hour: 8, minute: 53, red: ['3648', '2996', '9134'], blue: ['8334', '10114', '662'], redScore: 223, blueScore: 75 },
  { num: 2, date: '2026-08-25', hour: 9, minute: 5, red: ['4293', '3807', '9586'], blue: ['4068', '1977', '4944'], redScore: 70, blueScore: 120 },
  { num: 3, date: '2026-08-25', hour: 9, minute: 18, red: ['2945', '9501', '4183'], blue: ['10333', '4499', '3288'], redScore: 30, blueScore: 230 },
  { num: 4, date: '2026-08-25', hour: 9, minute: 27, red: ['9068', '-4388', '2240'], blue: ['1339', '4550', '4418'], redScore: 412, blueScore: 100 },
  { num: 5, date: '2026-08-25', hour: 9, minute: 36, red: ['498', '2083', '8044'], blue: ['5493', '159', '1619'], redScore: 299, blueScore: 42 },
  { num: 6, date: '2026-08-25', hour: 9, minute: 48, red: ['6358', '11220', '2996'], blue: ['7485', '4068', '8334'], redScore: 212, blueScore: 144 },
  { num: 7, date: '2026-08-25', hour: 9, minute: 58, red: ['4418', '9501', '4499'], blue: ['10114', '3807', '4944'], redScore: 253, blueScore: 77 },
  { num: 8, date: '2026-08-25', hour: 10, minute: 7, red: ['4183', '662', '4550'], blue: ['4293', '1339', '5493'], redScore: 54, blueScore: 187 },
  { num: 9, date: '2026-08-25', hour: 10, minute: 16, red: ['3648', '11220', '3288'], blue: ['1977', '498', '9068'], redScore: 33, blueScore: 549 },
  { num: 10, date: '2026-08-25', hour: 10, minute: 24, red: ['159', '2240', '6358'], blue: ['1619', '2945', '8044'], redScore: 196, blueScore: 242 },
  { num: 11, date: '2026-08-25', hour: 10, minute: 34, red: ['2083', '9586', '-4388'], blue: ['7485', '9134', '10333'], redScore: 148, blueScore: 42 },
  { num: 12, date: '2026-08-25', hour: 10, minute: 48, red: ['5493', '4183', '4499'], blue: ['2996', '4068', '3807'], redScore: 199, blueScore: 216 },
  { num: 13, date: '2026-08-25', hour: 10, minute: 58, red: ['9068', '9501', '10114'], blue: ['2240', '4550', '3288'], redScore: 221, blueScore: 127 },
  { num: 14, date: '2026-08-25', hour: 11, minute: 9, red: ['4418', '8044', '159'], blue: ['-4388', '662', '7485'], redScore: 181, blueScore: 98 },
  { num: 15, date: '2026-08-25', hour: 11, minute: 18, red: ['2083', '9134', '1619'], blue: ['3648', '1977', '2945'], redScore: 238, blueScore: 59 },
  { num: 16, date: '2026-08-25', hour: 11, minute: 27, red: ['10333', '1339', '6358'], blue: ['498', '4293', '11220'], redScore: 143, blueScore: 210 },
  { num: 17, date: '2026-08-25', hour: 11, minute: 36, red: ['9586', '4944', '2240'], blue: ['8334', '3288', '2996'], redScore: 107, blueScore: 164 },
  { num: 18, date: '2026-08-25', hour: 11, minute: 45, red: ['1619', '1977', '-4388'], blue: ['662', '4068', '9501'], redScore: 249, blueScore: 133 },
  { num: 19, date: '2026-08-25', hour: 11, minute: 55, red: ['5493', '8044', '10333'], blue: ['159', '3807', '9068'], redScore: 243, blueScore: 259 },
  { num: 20, date: '2026-08-25', hour: 12, minute: 5, red: ['2083', '4418', '3648'], blue: ['11220', '9586', '1339'], redScore: 47, blueScore: 166 },
  { num: 21, date: '2026-08-26', hour: 8, minute: 53, red: ['4293', '4944', '7485'], blue: ['2945', '4499', '9134'], redScore: 139, blueScore: 171 },
  { num: 22, date: '2026-08-25', hour: 13, minute: 16, red: ['8334', '6358', '4183'], blue: ['4550', '10114', '498'], redScore: 66, blueScore: 326 },
  { num: 23, date: '2026-08-25', hour: 13, minute: 27, red: ['11220', '3807', '5493'], blue: ['3648', '-4388', '8044'], redScore: 22, blueScore: 245 },
  { num: 24, date: '2026-08-25', hour: 13, minute: 36, red: ['3288', '1339', '662'], blue: ['4499', '4293', '1619'], redScore: 145, blueScore: 334 },
  { num: 25, date: '2026-08-25', hour: 13, minute: 45, red: ['9134', '4550', '9586'], blue: ['7485', '159', '498'], redScore: 76, blueScore: 333 },
  { num: 26, date: '2026-08-25', hour: 13, minute: 55, red: ['1977', '8334', '10333'], blue: ['6358', '4418', '4944'], redScore: 53, blueScore: 64 },
  { num: 27, date: '2026-08-25', hour: 14, minute: 4, red: ['4183', '4068', '10114'], blue: ['2083', '2240', '2945'], redScore: 92, blueScore: 49 },
  { num: 28, date: '2026-08-25', hour: 14, minute: 14, red: ['9068', '2996', '4293'], blue: ['8044', '9134', '9501'], redScore: 405, blueScore: 306 },
  { num: 29, date: '2026-08-25', hour: 14, minute: 24, red: ['11220', '4499', '4550'], blue: ['1977', '3288', '4418'], redScore: 158, blueScore: 27 },
  { num: 30, date: '2026-08-25', hour: 14, minute: 33, red: ['-4388', '8334', '4944'], blue: ['159', '2083', '4183'], redScore: 190, blueScore: 76 },
  { num: 31, date: '2026-08-25', hour: 14, minute: 43, red: ['9501', '7485', '3807'], blue: ['2240', '3648', '1339'], redScore: 48, blueScore: 296 },
  { num: 32, date: '2026-08-25', hour: 14, minute: 53, red: ['2996', '498', '1619'], blue: ['6358', '10114', '5493'], redScore: 493, blueScore: 79 },
  { num: 33, date: '2026-08-25', hour: 15, minute: 3, red: ['2945', '10333', '662'], blue: ['4068', '9068', '9586'], redScore: 31, blueScore: 279 },
  { num: 34, date: '2026-08-25', hour: 15, minute: 14, red: ['3807', '4183', '4418'], blue: ['9501', '3288', '2083'], redScore: 66, blueScore: 53 },
  { num: 35, date: '2026-08-25', hour: 15, minute: 23, red: ['8044', '11220', '1977'], blue: ['2240', '4499', '10114'], redScore: 210, blueScore: 337 },
  { num: 36, date: '2026-08-25', hour: 15, minute: 32, red: ['4944', '5493', '498'], blue: ['9068', '8334', '3648'], redScore: 433, blueScore: 261 },
  { num: 37, date: '2026-08-25', hour: 15, minute: 46, red: ['1619', '662', '9586'], blue: ['4550', '10333', '-4388'], redScore: 83, blueScore: 134 },
  { num: 38, date: '2026-08-25', hour: 15, minute: 54, red: ['1339', '2996', '159'], blue: ['6358', '4293', '2945'], redScore: 216, blueScore: 84 },
  { num: 39, date: '2026-08-25', hour: 16, minute: 2, red: ['9134', '5493', '4068'], blue: ['4418', '7485', '11220'], redScore: 193, blueScore: 64 },
  { num: 40, date: '2026-08-25', hour: 16, minute: 11, red: ['3288', '4944', '2083'], blue: ['662', '8044', '3807'], redScore: 161, blueScore: 254 },
  { num: 41, date: '2026-08-25', hour: 16, minute: 19, red: ['159', '2945', '8334'], blue: ['4550', '9501', '1977'], redScore: 87, blueScore: 111 },
  { num: 42, date: '2026-08-25', hour: 16, minute: 31, red: ['10114', '1339', '9134'], blue: ['4499', '-4388', '4068'], redScore: 143, blueScore: 234 },
  { num: 43, date: '2026-08-25', hour: 16, minute: 40, red: ['2240', '10333', '4293'], blue: ['498', '3648', '6358'], redScore: 234, blueScore: 261 },
  { num: 44, date: '2026-08-25', hour: 16, minute: 50, red: ['9586', '7485', '2996'], blue: ['4183', '1619', '9068'], redScore: 142, blueScore: 241 },
  { num: 45, date: '2026-08-25', hour: 17, minute: 0, red: ['3807', '2945', '4550'], blue: ['8334', '5493', '4418'], redScore: 27, blueScore: 37 },
  { num: 46, date: '2026-08-25', hour: 17, minute: 10, red: ['1977', '6358', '9134'], blue: ['1339', '-4388', '9501'], redScore: 152, blueScore: 220 },
  { num: 47, date: '2026-08-25', hour: 17, minute: 19, red: ['4499', '159', '3648'], blue: ['4183', '2240', '7485'], redScore: 215, blueScore: 118 },
  { num: 48, date: '2026-08-25', hour: 17, minute: 29, red: ['10114', '4293', '2083'], blue: ['11220', '9068', '662'], redScore: 103, blueScore: 305 },
  { num: 49, date: '2026-08-26', hour: 9, minute: 1, red: ['3288', '8044', '4068'], blue: ['10333', '9586', '498'], redScore: 305, blueScore: 194 },
  { num: 50, date: '2026-08-26', hour: 9, minute: 19, red: ['2996', '4944', '4499'], blue: ['1619', '6358', '4550'], redScore: 221, blueScore: 95 },
  { num: 51, date: '2026-08-26', hour: 9, minute: 29, red: ['4293', '4418', '-4388'], blue: ['9501', '3648', '5493'], redScore: 91, blueScore: 72 },
  { num: 52, date: '2026-08-26', hour: 9, minute: 38, red: ['498', '2240', '3807'], blue: ['662', '9586', '1977'], redScore: 434, blueScore: 147 },
  { num: 53, date: '2026-08-26', hour: 9, minute: 46, red: ['7485', '9068', '3288'], blue: ['1339', '2083', '8334'], redScore: 209, blueScore: 154 },
  { num: 54, date: '2026-08-26', hour: 9, minute: 56, red: ['10333', '1619', '10114'], blue: ['4944', '9134', '159'], redScore: 132, blueScore: 157 },
  { num: 55, date: '2026-08-26', hour: 10, minute: 5, red: ['2945', '11220', '4068'], blue: ['8044', '4183', '2996'], redScore: 98, blueScore: 381 },
  { num: 56, date: '2026-08-26', hour: 10, minute: 15, red: ['5493', '9068', '2083'], blue: ['9586', '6358', '4499'], redScore: 139, blueScore: 138 },
  { num: 57, date: '2026-08-26', hour: 10, minute: 26, red: ['4418', '1619', '2240'], blue: ['9134', '8334', '4293'], redScore: 273, blueScore: 92 },
  { num: 58, date: '2026-08-26', hour: 10, minute: 34, red: ['662', '498', '9501'], blue: ['4944', '4183', '11220'], redScore: 326, blueScore: 30 },
  { num: 59, date: '2026-08-26', hour: 10, minute: 42, red: ['8044', '7485', '1339'], blue: ['10114', '2996', '1977'], redScore: 382, blueScore: 216 },
  { num: 60, date: '2026-08-26', hour: 10, minute: 52, red: ['4068', '4550', '159'], blue: ['3807', '10333', '3648'], redScore: 117, blueScore: 43 },
  { num: 61, date: '2026-08-26', hour: 11, minute: 2, red: ['-4388', '5493', '2945'], blue: ['3288', '498', '4183'], redScore: 25, blueScore: 326 },
  { num: 62, date: '2026-08-26', hour: 11, minute: 10, red: ['9501', '1619', '8334'], blue: ['9586', '10114', '8044'], redScore: 255, blueScore: 346 },
  { num: 63, date: '2026-08-26', hour: 11, minute: 23, red: ['4499', '1977', '1339'], blue: ['2996', '4418', '10333'], redScore: 154, blueScore: 129 },
  { num: 64, date: '2026-08-26', hour: 11, minute: 34, red: ['4068', '3648', '4293'], blue: ['4550', '2083', '7485'], redScore: 110, blueScore: 91 },
  { num: 65, date: '2026-08-26', hour: 11, minute: 43, red: ['4944', '2945', '9068'], blue: ['-4388', '159', '11220'], redScore: 388, blueScore: 195 },
  { num: 66, date: '2026-08-26', hour: 11, minute: 56, red: ['3807', '3288', '6358'], blue: ['9134', '662', '2240'], redScore: 59, blueScore: 183 },
];


function fakePracticeScore(seed) {
  const rand = (n) => {
    const x = Math.sin(n) * 10000;
    return x - Math.floor(x);
  };
  return {
    redScore: Math.round(40 + rand(seed) * 380),
    blueScore: Math.round(40 + rand(seed + 0.5) * 380),
  };
}

function fakePracticeMatches() {
  const nowSec = Date.now() / 1000;
  return FAKE_PRACTICE_SCHEDULE.map((p) => {
    const t = fakeMstEpochSeconds(p.date, p.hour, p.minute);
    const played = nowSec >= t;
    const { redScore, blueScore } = fakePracticeScore(p.num);
    return {
      key: `${FAKE_EVENT_KEY}_p${p.num}`,
      comp_level: 'p',
      match_number: p.num,
      set_number: 1,
      predicted_time: t,
      actual_time: played ? t : null,
      alliances: {
        red: { team_keys: p.red.map((n) => `frc${n}`), score: played ? redScore : -1 },
        blue: { team_keys: p.blue.map((n) => `frc${n}`), score: played ? blueScore : -1 },
      },
    };
  });
}

function fakeQualsMatches() {
  const nowSec = Date.now() / 1000;
  return FAKE_QUALS_SCHEDULE.map((q) => {
    const t = fakeMstEpochSeconds(q.date, q.hour, q.minute);
    const played = nowSec >= t;
    return {
      key: `${FAKE_EVENT_KEY}_qm${q.num}`,
      comp_level: 'qm',
      match_number: q.num,
      set_number: 1,
      predicted_time: t,
      actual_time: played ? t : null,
      alliances: {
        red: { team_keys: q.red.map((n) => `frc${n}`), score: played ? q.redScore : -1 },
        blue: { team_keys: q.blue.map((n) => `frc${n}`), score: played ? q.blueScore : -1 },
      },
    };
  });
}

function fakeMatches() {
  return [...fakePracticeMatches(), ...fakeQualsMatches()];
}

function fakePlayedQualsSoFar() {
  const nowSec = Date.now() / 1000;
  return FAKE_QUALS_SCHEDULE.filter((q) => nowSec >= fakeMstEpochSeconds(q.date, q.hour, q.minute));
}

function solveLinearSystem(A, b) {
  const n = b.length;
  for (let col = 0; col < n; col++) {
    let pivot = col;
    for (let row = col + 1; row < n; row++) {
      if (Math.abs(A[row][col]) > Math.abs(A[pivot][col])) pivot = row;
    }
    [A[col], A[pivot]] = [A[pivot], A[col]];
    [b[col], b[pivot]] = [b[pivot], b[col]];
    if (Math.abs(A[col][col]) < 1e-9) continue;
    for (let row = 0; row < n; row++) {
      if (row === col) continue;
      const factor = A[row][col] / A[col][col];
      if (factor === 0) continue;
      for (let c = col; c < n; c++) A[row][c] -= factor * A[col][c];
      b[row] -= factor * b[col];
    }
  }
  return b.map((v, i) => (Math.abs(A[i][i]) < 1e-9 ? 0 : v / A[i][i]));
}

function computeFakeOprs() {
  const played = fakePlayedQualsSoFar();
  const teamKeys = [...new Set(played.flatMap((q) => [...q.red, ...q.blue]))].map((n) => `frc${n}`);
  if (teamKeys.length === 0) return {};
  const index = new Map(teamKeys.map((k, i) => [k, i]));
  const n = teamKeys.length;
  const AtA = Array.from({ length: n }, () => new Array(n).fill(0));
  const Atb = new Array(n).fill(0);
  for (const q of played) {
    for (const [teams, score] of [[q.red, q.redScore], [q.blue, q.blueScore]]) {
      const idxs = teams.map((t) => index.get(`frc${t}`));
      for (const i of idxs) {
        Atb[i] += score;
        for (const j of idxs) AtA[i][j] += 1;
      }
    }
  }
  for (let i = 0; i < n; i++) AtA[i][i] += 1;
  const solved = solveLinearSystem(AtA, Atb);
  const result = {};
  teamKeys.forEach((k, i) => { result[k] = Math.max(0, Number(solved[i].toFixed(2))); });
  return result;
}

function fakeOprs() {
  return computeFakeOprs();
}

function computeFakeStandings() {
  const played = fakePlayedQualsSoFar();
  const oprs = computeFakeOprs();
  const record = new Map();
  const bump = (team, key) => {
    const r = record.get(team) || { wins: 0, losses: 0, ties: 0 };
    r[key]++;
    record.set(team, r);
  };
  for (const q of played) {
    if (q.redScore > q.blueScore) {
      q.red.forEach((t) => bump(t, 'wins'));
      q.blue.forEach((t) => bump(t, 'losses'));
    } else if (q.blueScore > q.redScore) {
      q.blue.forEach((t) => bump(t, 'wins'));
      q.red.forEach((t) => bump(t, 'losses'));
    } else {
      q.red.forEach((t) => bump(t, 'ties'));
      q.blue.forEach((t) => bump(t, 'ties'));
    }
  }
  const allTeams = [...new Set(FAKE_QUALS_SCHEDULE.flatMap((q) => [...q.red, ...q.blue]))];
  const rows = allTeams.map((team) => {
    const r = record.get(team) || { wins: 0, losses: 0, ties: 0 };
    return {
      team_number: team,
      name: team === FAKE_TEAM_NUMBER ? 'Ridgebotics (test)' : `Team ${team}`,
      opr: oprs[`frc${team}`] ?? null,
      wins: r.wins,
      losses: r.losses,
      ties: r.ties,
    };
  });
  rows.sort((a, b) => (b.wins * 2 + b.ties) - (a.wins * 2 + a.ties) || (b.opr ?? 0) - (a.opr ?? 0));
  rows.forEach((row, i) => { row.rank = i + 1; });
  return rows;
}

function fakeStatus() {
  const standings = computeFakeStandings();
  const me = standings.find((r) => r.team_number === FAKE_TEAM_NUMBER);
  if (!me) return { qual: { ranking: null, num_teams: standings.length } };
  return {
    qual: {
      ranking: { rank: me.rank, record: { wins: me.wins, losses: me.losses, ties: me.ties } },
      num_teams: standings.length,
    },
  };
}

function fakeEventTeamsList() {
  const allTeams = [...new Set(FAKE_QUALS_SCHEDULE.flatMap((q) => [...q.red, ...q.blue]))];
  return allTeams
    .sort((a, b) => Math.abs(Number(a)) - Math.abs(Number(b)))
    .map((n) => ({
      team_number: n,
      name: n === FAKE_TEAM_NUMBER ? 'Ridgebotics (test)' : `Team ${n}`,
    }));
}

function fakeEventStats() {
  return computeFakeStandings();
}

const VAPID_PUBLIC_KEY = process.env.VAPID_PUBLIC_KEY;
const VAPID_PRIVATE_KEY = process.env.VAPID_PRIVATE_KEY;
const VAPID_SUBJECT = process.env.VAPID_SUBJECT;
const PUSH_CHECK_SECRET = process.env.PUSH_CHECK_SECRET;
const REPORTS_ADMIN_SECRET = process.env.REPORTS_ADMIN_SECRET;

const webpushConfigured = Boolean(VAPID_PUBLIC_KEY && VAPID_PRIVATE_KEY && VAPID_SUBJECT);
if (webpushConfigured) {
  webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);
} else {
  console.warn('VAPID keys not fully configured. /push/* routes will be disabled');
}

const PUSH_BURST_COUNT = Number(process.env.PUSH_BURST_COUNT || 3);
const PUSH_BURST_INTERVAL_MS = Number(process.env.PUSH_BURST_INTERVAL_MS || 200);


const PUSH_VIBRATE_PATTERN = [200, 100, 300, 200, 300];

async function sendSingleNotification(sub, payload) {
  try {
    await webpush.sendNotification(sub.subscription, payload);
    return true;
  } catch (err) {
    console.error(`webpush send failed (status ${err.statusCode}): ${err.body || err.message}`);
    if (err.statusCode === 404 || err.statusCode === 410) {
      await pushSubscriptionsCollection.deleteOne({ endpoint: sub.subscription.endpoint });
    }
    return false;
  }
}

async function sendPushBurst(sub, basePayload, tagSeed) {
  const isIos = sub.platform === 'ios';
  const payload = JSON.stringify({
    ...basePayload,
    tag: tagSeed,
    renotify: true,
    ...(isIos ? {} : { vibrate: PUSH_VIBRATE_PATTERN }),
  });

  // if (!isIos) {
    return sendSingleNotification(sub, payload);
  // }

  // let deliveredAtLeastOnce = false;
  // for (let i = 0; i < PUSH_BURST_COUNT; i++) {
  //   const delivered = await sendSingleNotification(sub, payload);
  //   if (!delivered) {

  //     break;
  //   }
  //   deliveredAtLeastOnce = true;
  //   if (i < PUSH_BURST_COUNT - 1) {
  //     await sleep(PUSH_BURST_INTERVAL_MS);
  //   }
  // }
  // return deliveredAtLeastOnce;
}

if (!MONGODB_URI) {
  console.error('Missing MONGODB_URI');
  process.exit(1);
}

const corsOptions = {
  origin: FRONTEND_ORIGIN,
  methods: ['GET', 'POST', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'X-Reports-Admin-Secret'],
};

app.use(cors(corsOptions));
app.options('*', cors(corsOptions));
app.use(express.json({ limit: '50mb' }));

const mongoClient = new MongoClient(MONGODB_URI);
let teamsCollection;
let batteriesCollection;
let pushSubscriptionsCollection;
let notifiedMatchesCollection;
let eventRostersCollection;
let reportsCollection;
let worldRatingsCollection;
let eventTeamsCollection;
let countersCollection;
let worldRatingRefresh;

async function connectToMongo() {
  await mongoClient.connect();

  const db = mongoClient.db(DB_NAME);
  teamsCollection = db.collection('teams');
  batteriesCollection = db.collection('batteries');
  pushSubscriptionsCollection = db.collection('pushSubscriptions');
  notifiedMatchesCollection = db.collection('notifiedMatches');
  eventRostersCollection = db.collection('eventRosters');
  reportsCollection = db.collection('reports');
  worldRatingsCollection = db.collection('worldRatings');
  eventTeamsCollection = db.collection('eventTeams');
  countersCollection = db.collection('counters');

  await teamsCollection.createIndex({ teamNumber: 1 }, { unique: true });
  await batteriesCollection.createIndex({ teamNumber: 1, label: 1 }, { unique: true });
  await batteriesCollection.createIndex({ teamNumber: 1, lastUsedAt: 1 });
  await pushSubscriptionsCollection.createIndex({ endpoint: 1 }, { unique: true });
  await pushSubscriptionsCollection.createIndex({ teamNumber: 1, eventKey: 1 });
  await notifiedMatchesCollection.createIndex(
    { teamNumber: 1, eventKey: 1, matchKey: 1 },
    { unique: true },
  );

  await notifiedMatchesCollection.createIndex(
    { createdAt: 1 },
    { expireAfterSeconds: 7 * 24 * 60 * 60 },
  );
  await eventRostersCollection.createIndex({ teamNumber: 1, eventKey: 1 }, { unique: true });
  await reportsCollection.createIndex({ createdAt: -1 });
  await reportsCollection.createIndex({ findingType: 1, errorType: 1, createdAt: -1 });
  await reportsCollection.createIndex({ scanId: 1, findingId: 1 });
  await worldRatingsCollection.createIndex({ refreshedAt: -1 });
  await eventTeamsCollection.createIndex({ refreshedAt: -1 });

  console.log(`Connected to MongoDB database: ${DB_NAME}`);
}

async function getFIRSTTeamName(teamNumber) {
  try {
    const response = await fetch(
      `https://frc-api.firstinspires.org/v3.0/2026/teams?teamNumber=${teamNumber}`,
      {
        headers: {
          Authorization:
            'Basic ' +
            Buffer.from(
              `${FIRST_USERNAME}:${FIRST_TOKEN}`
            ).toString('base64'),
        },
      }
    );

    const data = await response.json();

    if (data.teams && data.teams.length > 0) {
      return data.teams[0].nameShort;
    }

    return null;

  } catch (err) {
    console.error("FIRST lookup failed:", err);
    return null;
  }
}

async function tbaGet(path) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12000);
  let res;
  try {
    res = await fetch(`${TBA_BASE}${path}`, {
      headers: { 'X-TBA-Auth-Key': TBA_AUTH_KEY }, signal: controller.signal,
    });
  } catch (err) {
    if (err.name === 'AbortError') {
      const timeoutError = new Error(`TBA ${path} timed out`);
      timeoutError.status = 504;
      throw timeoutError;
    }
    throw err;
  } finally {
    clearTimeout(timeout);
  }
  if (!res.ok) {
    const err = new Error(`TBA ${path} failed: ${res.status}`);
    err.status = res.status;
    throw err;
  }
  return res.json();
}


async function tbaGetOprs(eventKey) {
  try {
    const data = await tbaGet(`/event/${eventKey}/oprs`);
    return data && typeof data === 'object' ? data : { oprs: {} };
  } catch (err) {
    return { oprs: {} };
  }
}

function cleanString(value) {
  if (value === undefined || value === null) return null;
  const cleaned = String(value).trim();
  return cleaned || null;
}

function checkReportsAdmin(req, res) {
  if (!REPORTS_ADMIN_SECRET) {
    res.status(503).json({ error: 'Report dashboard is not configured' });
    return false;
  }
  if (req.get('X-Reports-Admin-Secret') !== REPORTS_ADMIN_SECRET) {
    res.status(401).json({ error: 'Unauthorized' });
    return false;
  }
  return true;
}

async function getTeam(teamNumber) {
  const cleanedTeamNumber = cleanString(teamNumber);
  if (!cleanedTeamNumber) return null;
  return teamsCollection.findOne({ teamNumber: cleanedTeamNumber });
}

async function checkTeamAuth(req, res) {
  const teamNumber = cleanString(req.body.teamNumber || req.query.teamNumber);
  const passcode = cleanString(req.body.passcode || req.query.passcode);

  if (!teamNumber || !passcode) {
    res.status(400).json({ error: 'teamNumber and passcode required' });
    return null;
  }

  const team = await getTeam(teamNumber);
  if (!team || team.passcode !== passcode) {
    res.status(401).json({ error: 'Invalid team number or passcode' });
    return null;
  }

  return team;
}

function fallbackRecommendation(batteries, reason = 'Most rested available battery') {
  const available = batteries.find((battery) => !battery.isInUse && !battery.isCharging);
  const picked = available || batteries[0];

  return {
    recommendedLabel: picked ? picked.label : null,
    reason: picked ? reason : 'No batteries logged yet',
  };
}

async function incrementScanCount() {
  if (!countersCollection) return;
  try {
    await countersCollection.updateOne(
      { _id: 'scans' },
      { $inc: { count: 1 } },
      { upsert: true },
    );
  } catch (err) {
    console.error('Scan counter increment failed:', err);
  }
}

app.get('/', (req, res) => {
  res.send('Backend running');
});

app.get('/health', (req, res) => {
  res.json({
    ok: true,
    mongo: Boolean(teamsCollection && batteriesCollection),
    reportsMongo: Boolean(reportsCollection),
    geminiConfigured: Boolean(GEMINI_API_KEY),
    tbaConfigured: Boolean(TBA_AUTH_KEY),
    webpushConfigured,
  });
});

app.get('/scans/count', async (req, res) => {
  if (!countersCollection) {
    return res.status(503).json({ error: 'Scan counter is not configured' });
  }
  try {
    const doc = await countersCollection.findOne({ _id: 'scans' });
    res.json({ totalScans: doc?.count || 0 });
  } catch (err) {
    console.error('Scan count fetch error:', err);
    res.status(500).json({ error: 'Could not load scan count' });
  }
});

app.post('/analyzeImage', async (req, res) => {
  try {
    if (!GEMINI_API_KEY) {
      return res.status(503).json({ error: 'GEMINI_API_KEY is not configured on the server' });
    }

    const { status, data } = await callGeminiWithRetry(
      `${GEMINI_SCAN_URL}?key=${GEMINI_API_KEY}`,
      req.body,
    );
    if (status >= 200 && status < 300) {
      incrementScanCount();
    }
    res.status(status).json(data);
  } catch (err) {
    console.error('Analyze image error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/reportFinding', async (req, res) => {
  if (!reportsCollection) {
    return res.status(503).json({ error: 'Scan reporting is not configured' });
  }

  const title = cleanString(req.body.title);
  const scanId = cleanString(req.body.scanId);
  const findingId = cleanString(req.body.findingId);
  const errorType = cleanString(req.body.errorType) || 'other';
  const allowedErrorTypes = new Set([
    'false_positive',
    'wrong_location',
    'wrong_description',
    'missed_problem',
    'other',
  ]);

  if (!title || !scanId || !findingId) {
    return res.status(400).json({ error: 'scanId, findingId, and title are required' });
  }
  if (!allowedErrorTypes.has(errorType)) {
    return res.status(400).json({ error: 'Invalid errorType' });
  }

  const report = {
    scanId,
    findingId,
    scanMode: cleanString(req.body.scanMode) || 'physical',
    errorType,
    findingType: title.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, ''),
    title,
    description: cleanString(req.body.description) || '',
    userComment: cleanString(req.body.userComment) || '',
    severity: cleanString(req.body.severity) || 'unknown',
    status: 'pending',
    createdAt: new Date(),
  };

  try {
    const result = await reportsCollection.insertOne(report);
    res.status(201).json({ ok: true, reportId: result.insertedId.toString() });
  } catch (err) {
    console.error('Report finding error:', err);
    res.status(500).json({ error: 'Could not save report' });
  }
});

app.get('/reports', async (req, res) => {
  if (!checkReportsAdmin(req, res)) return;
  if (!reportsCollection) {
    return res.status(503).json({ error: 'Scan reporting is not configured' });
  }
  try {
    const reports = await reportsCollection.find({}).sort({ createdAt: -1 }).limit(50).toArray();
    res.json({ reports });
  } catch (err) {
    console.error('List reports error:', err);
    res.status(500).json({ error: 'Could not load reports' });
  }
});

app.get('/reports/summary', async (req, res) => {
  if (!checkReportsAdmin(req, res)) return;
  if (!reportsCollection) {
    return res.status(503).json({ error: 'Scan reporting is not configured' });
  }
  try {
    const summary = await reportsCollection.aggregate([
      { $group: { _id: { findingType: '$findingType', errorType: '$errorType' }, count: { $sum: 1 } } },
      { $sort: { count: -1 } },
    ]).toArray();
    res.json({ summary });
  } catch (err) {
    console.error('Report summary error:', err);
    res.status(500).json({ error: 'Could not load report summary' });
  }
});

app.post('/battery/register', async (req, res) => {
  try {
    const teamNumber = cleanString(req.body.teamNumber);
    const passcode = cleanString(req.body.passcode);

    if (!teamNumber || !passcode) {
      return res.status(400).json({ error: 'teamNumber and passcode required' });
    }

    if (passcode.length < 4) {
      return res.status(400).json({ error: 'Passcode must be at least 4 characters' });
    }

    const existing = await getTeam(teamNumber);
    if (existing) {
      return res.status(409).json({ error: 'Team already registered. \n\nClick the report button on the bottom right corner of the home page if you don\'t have access to your team account.' });
    }

const teamName = await getFIRSTTeamName(teamNumber);

    await teamsCollection.insertOne({
      teamNumber,
      passcode,
      teamName,
      createdAt: new Date().toISOString(),
    });

    res.json({ ok: true, teamName });
  } catch (err) {
    console.error('Register error:', err);

    if (err.code === 11000) {
      return res.status(409).json({ error: 'Team already registered. \n\nClick the report button on the bottom right corner of the home page if you don\'t have access to your team account.' });
    }

    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/login', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    res.json({ ok: true, teamName: team.teamName || null });
  } catch (err) {
    console.error('Login error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/changeTeamName', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const teamName = cleanString(req.body.teamName);

    await teamsCollection.updateOne(
      { teamNumber: team.teamNumber },
      { $set: { teamName } },
    );

    res.json({ ok: true, teamName });
  } catch (err) {
    console.error('Change team name error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/changePasscode', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const newPasscode = cleanString(req.body.newPasscode);
    if (!newPasscode || newPasscode.length < 4) {
      return res.status(400).json({ error: 'New passcode must be at least 4 characters' });
    }

    await teamsCollection.updateOne(
      { teamNumber: team.teamNumber },
      { $set: { passcode: newPasscode } },
    );

    res.json({ ok: true });
  } catch (err) {
    console.error('Change passcode error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/reset', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const result = await batteriesCollection.deleteMany({ teamNumber: team.teamNumber });
    res.json({ ok: true, deletedCount: result.deletedCount });
  } catch (err) {
    console.error('Reset error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.get('/battery/list', async (req, res) => {
  try {
    const teamNumber = cleanString(req.query.teamNumber);
    const passcode = cleanString(req.query.passcode);
    const guest = req.query.guest === 'true';

    if (!teamNumber) {
      return res.status(400).json({ error: 'teamNumber required' });
    }

    const team = await getTeam(teamNumber);
    if (!team) {
      return res.status(404).json({ error: 'Team not found' });
    }

    if (!guest && team.passcode !== passcode) {
      return res.status(401).json({ error: 'Invalid team number or passcode' });
    }

    const batteries = await batteriesCollection
      .find({ teamNumber })
      .sort({ lastUsedAt: 1 })
      .toArray();

    res.json({ batteries, teamName: team.teamName || null });
  } catch (err) {
    console.error('List error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/add', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const count = await batteriesCollection.countDocuments({ teamNumber: team.teamNumber });
    const label = `B${count + 1}`;
    const battery = {
      teamNumber: team.teamNumber,
      label,
      lastUsedAt: new Date(0).toISOString(),
      flags: [],
      isCharging: false,
      isInUse: false,
      createdAt: new Date().toISOString(),
    };

    await batteriesCollection.insertOne(battery);
    res.json({ battery });
  } catch (err) {
    console.error('Add battery error:', err);

    if (err.code === 11000) {
      return res.status(409).json({ error: 'Battery already exists' });
    }

    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/use', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const label = cleanString(req.body.label);
    if (!label) {
      return res.status(400).json({ error: 'label is required' });
    }

    const battery = await batteriesCollection.findOne({ teamNumber: team.teamNumber, label });
    if (!battery) {
      return res.status(404).json({ error: 'Battery not found' });
    }

    const nextInUse = !battery.isInUse;

    await batteriesCollection.updateOne(
      { teamNumber: team.teamNumber, label },
      {
        $set: {
          isInUse: nextInUse,
          isCharging: false,
          lastUsedAt: new Date().toISOString(),
        },
      },
    );

    res.json({ ok: true, isInUse: nextInUse });
  } catch (err) {
    console.error('Use battery error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/charging', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const label = cleanString(req.body.label);
    if (!label) {
      return res.status(400).json({ error: 'label is required' });
    }

    const battery = await batteriesCollection.findOne({ teamNumber: team.teamNumber, label });
    if (!battery) {
      return res.status(404).json({ error: 'Battery not found' });
    }

    const nextCharging = !battery.isCharging;

    await batteriesCollection.updateOne(
      { teamNumber: team.teamNumber, label },
      {
        $set: {
          isCharging: nextCharging,
          isInUse: false,
          chargedAt: nextCharging ? new Date().toISOString() : battery.chargedAt || null,
        },
      },
    );

    res.json({ ok: true, isCharging: nextCharging });
  } catch (err) {
    console.error('Charging battery error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/flag', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const label = cleanString(req.body.label);
    if (!label) {
      return res.status(400).json({ error: 'label is required' });
    }

    const result = await batteriesCollection.updateOne(
      { teamNumber: team.teamNumber, label },
      {
        $push: {
          flags: {
            note: cleanString(req.body.note) || '',
            flaggedAt: new Date().toISOString(),
          },
        },
      },
    );

    if (result.matchedCount === 0) {
      return res.status(404).json({ error: 'Battery not found' });
    }

    res.json({ ok: true });
  } catch (err) {
    console.error('Flag error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.delete('/battery/:label', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const result = await batteriesCollection.deleteOne({
      teamNumber: team.teamNumber,
      label: req.params.label,
    });

    res.json({ ok: true, deletedCount: result.deletedCount });
  } catch (err) {
    console.error('Delete battery error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/battery/recommend', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const batteries = await batteriesCollection
      .find({ teamNumber: team.teamNumber })
      .sort({ lastUsedAt: 1 })
      .toArray();

    if (batteries.length === 0) {
      return res.json({ recommendedLabel: null, reason: 'No batteries logged yet' });
    }

    if (!GEMINI_API_KEY) {
      return res.json(fallbackRecommendation(batteries));
    }

    const chargeMinutes = 45;
    const summary = batteries
      .map((battery) => {
        const restMinutes = Math.round(
          (Date.now() - new Date(battery.lastUsedAt).getTime()) / 60000,
        );

        const chargingStatus = battery.isInUse
          ? 'currently in use'
          : battery.isCharging
            ? (() => {
                const chargedAt = battery.chargedAt
                  ? new Date(battery.chargedAt).getTime()
                  : Date.now();
                const elapsedMin = Math.round((Date.now() - chargedAt) / 60000);
                const remaining = Math.max(0, chargeMinutes - elapsedMin);
                return remaining > 0 ? `charging (${remaining}min left)` : 'charging (ready)';
              })()
            : 'available';

        const flags = Array.isArray(battery.flags) ? battery.flags : [];
        const flagSummary =
          flags.length === 0
            ? 'no flags'
            : `flagged ${flags.length}x, reasons: ${flags
                .map((flag) => flag.note || 'no reason given')
                .join('; ')}`;

        return `${battery.label}: charged ${restMinutes} minutes ago, status: ${chargingStatus}, ${flagSummary}`;
      })
      .join('\n');

    const { status, data } = await callGeminiWithRetry(
      `${GEMINI_TEXT_URL}?key=${GEMINI_API_KEY}`,
      {
        contents: [
          {
            parts: [
              {
                text: `Here is battery data for an FRC robotics team preparing for a match:\n\n${summary}\n\nBased on this, which single battery should they grab next? Prefer available batteries that were charged longest ago (most rested). Avoid batteries currently in use or still charging. Heavily penalize batteries with flags mentioning serious issues like dying mid-match or brownouts. Respond ONLY with valid JSON, no markdown:\n\n{"recommendedLabel":"B1","reason":"one sentence reason under 15 words"}`,
              },
            ],
          },
        ],
        generationConfig: { temperature: 0, maxOutputTokens: 100 },
      },
    );
    const rawText = data.candidates?.[0]?.content?.parts?.[0]?.text
      ?.replace(/```json/g, '')
      ?.replace(/```/g, '')
      ?.trim();

    if (status < 200 || status >= 300 || !rawText) {
      return res.json(fallbackRecommendation(batteries));
    }

    try {
      const parsed = JSON.parse(rawText);
      return res.json({
        recommendedLabel: parsed.recommendedLabel || null,
        reason: parsed.reason || 'Recommended by battery history',
      });
    } catch (parseErr) {
      console.error('Gemini JSON parse error:', parseErr);
      return res.json(fallbackRecommendation(batteries));
    }
  } catch (err) {
    console.error('Recommend error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.get('/match/events', async (req, res) => {
  const teamNumber = cleanString(req.query.teamNumber);
  const year = cleanString(req.query.year);

  if (isFakeTeamNumber(teamNumber)) {
    return res.json([fakeEvent()]);
  }

  if (!TBA_AUTH_KEY) {
    return res.status(503).json({ error: 'TBA_AUTH_KEY is not configured on the server' });
  }
  if (!teamNumber || !year) {
    return res.status(400).json({ error: 'teamNumber and year are required' });
  }

  try {
    const events = await tbaGet(`/team/frc${teamNumber}/events/${year}/simple`);
    res.json(events);
  } catch (err) {
    console.error('Match events error:', err);
    res.status(err.status === 404 ? 404 : 500).json({ error: 'Could not load events' });
  }
});


app.get('/events', async (req, res) => {
  const year = cleanString(req.query.year) || String(new Date().getFullYear());

  if (!TBA_AUTH_KEY) {
    return res.status(503).json({ error: 'TBA_AUTH_KEY is not configured on the server' });
  }

  try {
    const events = await tbaGet(`/events/${year}/simple`);
    res.json(events);
  } catch (err) {
    console.error('Events list error:', err);
    res.status(err.status === 404 ? 404 : 500).json({ error: 'Could not load events' });
  }
});

app.get('/match/data', async (req, res) => {
  const teamNumber = cleanString(req.query.teamNumber);
  const eventKey = cleanString(req.query.eventKey);

  if (isFakeTeamNumber(teamNumber)) {
    return res.json({ matches: fakeMatches(), oprs: fakeOprs(), status: fakeStatus() });
  }

  if (!TBA_AUTH_KEY) {
    return res.status(503).json({ error: 'TBA_AUTH_KEY is not configured on the server' });
  }
  if (!teamNumber || !eventKey) {
    return res.status(400).json({ error: 'teamNumber and eventKey are required' });
  }

  const teamKey = `frc${teamNumber}`;
  try {
    const [matches, oprs, status] = await Promise.all([
      tbaGet(`/team/${teamKey}/event/${eventKey}/matches/simple`),
      tbaGetOprs(eventKey),
      tbaGet(`/team/${teamKey}/event/${eventKey}/status`).catch(() => null),
    ]);
    res.json({
      matches,
      oprs: oprs.oprs || {},
      status,
    });
  } catch (err) {
    console.error('Match data error:', err);
    res.status(err.status === 404 ? 404 : 500).json({ error: 'Could not load match data' });
  }
});


app.get('/event/matches', async (req, res) => {
  const eventKey = cleanString(req.query.eventKey);

  if (eventKey === FAKE_EVENT_KEY) {
    return res.json({ matches: fakeMatches() });
  }

  if (!TBA_AUTH_KEY) {
    return res.status(503).json({ error: 'TBA_AUTH_KEY is not configured on the server' });
  }
  if (!eventKey) {
    return res.status(400).json({ error: 'eventKey is required' });
  }

  try {
    const matches = await tbaGet(`/event/${eventKey}/matches/simple`);
    res.json({ matches });
  } catch (err) {
    console.error('Event matches error:', err);
    res.status(err.status === 404 ? 404 : 500).json({ error: 'Could not load event matches' });
  }
});

app.get('/event/alliances', async (req, res) => {
  const eventKey = cleanString(req.query.eventKey);

  if (eventKey === FAKE_EVENT_KEY) {
    return res.json({ alliances: [] });
  }

  if (!TBA_AUTH_KEY) {
    return res.status(503).json({ error: 'TBA_AUTH_KEY is not configured on the server' });
  }
  if (!eventKey) {
    return res.status(400).json({ error: 'eventKey is required' });
  }

  try {
    const alliances = await tbaGet(`/event/${eventKey}/alliances`);
    res.json({ alliances: alliances || [] });
  } catch (err) {
    console.error('Event alliances error:', err);
    res.status(err.status === 404 ? 404 : 500).json({ error: 'Could not load event alliances' });
  }
});

app.get('/event/roster', async (req, res) => {
  const teamNumber = cleanString(req.query.teamNumber);
  const eventKey = cleanString(req.query.eventKey);

  if (!teamNumber || !eventKey) {
    return res.status(400).json({ error: 'teamNumber and eventKey are required' });
  }

  try {
    const doc = await eventRostersCollection.findOne({ teamNumber, eventKey });
    res.json({ people: doc?.people || [] });
  } catch (err) {
    console.error('Roster fetch error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/event/roster/add', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const eventKey = cleanString(req.body.eventKey);
    const name = cleanString(req.body.name);
    if (!eventKey || !name) {
      return res.status(400).json({ error: 'eventKey and name are required' });
    }

    await eventRostersCollection.updateOne(
      { teamNumber: team.teamNumber, eventKey },
      { $addToSet: { people: name }, $set: { updatedAt: new Date().toISOString() } },
      { upsert: true },
    );

    res.json({ ok: true });
  } catch (err) {
    console.error('Roster add error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/event/roster/remove', async (req, res) => {
  try {
    const team = await checkTeamAuth(req, res);
    if (!team) return;

    const eventKey = cleanString(req.body.eventKey);
    const name = cleanString(req.body.name);
    if (!eventKey || !name) {
      return res.status(400).json({ error: 'eventKey and name are required' });
    }

    await eventRostersCollection.updateOne(
      { teamNumber: team.teamNumber, eventKey },
      { $pull: { people: name }, $set: { updatedAt: new Date().toISOString() } },
    );

    res.json({ ok: true });
  } catch (err) {
    console.error('Roster remove error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.get('/push/config', (req, res) => {
  if (!webpushConfigured) {
    return res.status(503).json({ error: 'Push notifications are not configured on the server' });
  }
  res.json({ vapidPublicKey: VAPID_PUBLIC_KEY });
});

app.post('/push/subscribe', async (req, res) => {
  if (!webpushConfigured) {
    return res.status(503).json({ error: 'Push notifications are not configured on the server' });
  }

  const teamNumber = cleanString(req.body.teamNumber);
  const eventKey = cleanString(req.body.eventKey);
  const subscription = req.body.subscription;
  const platform = cleanString(req.body.platform) === 'ios' ? 'ios' : 'web';

  if (!teamNumber || !eventKey || !subscription?.endpoint) {
    return res.status(400).json({ error: 'Missing fields' });
  }

  try {
    await pushSubscriptionsCollection.updateOne(
      { endpoint: subscription.endpoint },
      { $set: { teamNumber, eventKey, subscription, platform, updatedAt: new Date().toISOString() } },
      { upsert: true },
    );
    let testSent = false;
    try {
      testSent = await sendPushBurst(
      { subscription, platform },
      { title: 'RoboLens alerts are on', body: `You will get a reminder before Team ${teamNumber}'s matches.`, url: '/' },
      `confirm:${teamNumber}:${eventKey}`
      );
    } catch (err) {
    console.warn('Push test notification failed:', err.message);
    }
    res.json({ ok: true, testSent });
  } catch (err) {
    console.error('Push subscribe error:', err);
    res.status(500).json({ error: 'Could not save subscription' });
  }
});

app.post('/push/unsubscribe', async (req, res) => {
  const endpoint = cleanString(req.body.endpoint);
  if (!endpoint) {
    return res.status(400).json({ error: 'endpoint required' });
  }

  try {
    await pushSubscriptionsCollection.deleteOne({ endpoint });
    res.json({ ok: true });
  } catch (err) {
    console.error('Push unsubscribe error:', err);
    res.status(500).json({ error: 'Could not remove subscription' });
  }
});

app.get('/push/check', async (req, res) => {
  if (!webpushConfigured) {
    return res.status(503).json({ error: 'Push notifications are not fully configured' });
  }
  if (!PUSH_CHECK_SECRET || req.query.secret !== PUSH_CHECK_SECRET) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  try {
    const subs = await pushSubscriptionsCollection.find({}).toArray();
    if (subs.length === 0) {
      return res.json({ checked: 0, sent: 0 });
    }

    const groups = new Map();
    for (const sub of subs) {
      const key = `${sub.teamNumber}|${sub.eventKey}`;
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(sub);
    }

    let sent = 0;
    for (const [key, groupSubs] of groups) {
      try {
        const [teamNumber, eventKey] = key.split('|');
        const teamKey = `frc${teamNumber}`;
        const isFake = isFakeTeamNumber(teamNumber) && eventKey === FAKE_EVENT_KEY;

        let matches;
        if (isFake) {
          matches = fakeMatches();
        } else {
          if (!TBA_AUTH_KEY) continue;
          try {
            matches = await tbaGet(`/team/${teamKey}/event/${eventKey}/matches/simple`);
          } catch (err) {
            continue;
          }
        }

        matches = matches.filter(
          (m) =>
            m.alliances?.red?.team_keys?.includes(teamKey) ||
            m.alliances?.blue?.team_keys?.includes(teamKey),
        );

        const now = Date.now();
        const label = (match) =>
          match.comp_level === 'qm'
            ? `Quals ${match.match_number}`
            : `${match.comp_level.toUpperCase()} ${match.match_number}`;

        let oprMapPromise = null;
        const getOprMap = () => {
          if (!oprMapPromise) {
            oprMapPromise = isFake
              ? Promise.resolve(fakeOprs())
              : tbaGetOprs(eventKey).then((data) => data.oprs || {});
          }
          return oprMapPromise;
        };

        for (const match of matches) {
          const played =
            match.alliances?.red?.score >= 0 && match.alliances?.blue?.score >= 0;

          if (played) {
            const matchTimeSec = match.actual_time || match.predicted_time;
            if (!matchTimeSec) continue;
            const minsSincePlayed = (now - matchTimeSec * 1000) / 60000;
            if (minsSincePlayed < 0 || minsSincePlayed > FINAL_SCORE_WINDOW_MIN) continue;

            const finalMatchKey = `${match.key}::final`;
            const alreadyNotified = await notifiedMatchesCollection.findOne({
              teamNumber,
              eventKey,
              matchKey: finalMatchKey,
            });
            if (alreadyNotified) continue;

            const summary = finalScoreSummary(match, teamKey);
            const { title, body } = notificationForStage(teamNumber, label(match), 'final', { summary });
            const tagSeed = finalMatchKey;
            let deliveredAny = false;
            for (const sub of groupSubs) {
              if (await sendPushBurst(sub, { title, body, url: '/' }, tagSeed)) {
                sent++;
                deliveredAny = true;
              }
            }

            if (deliveredAny) {
              try {
                await notifiedMatchesCollection.insertOne({
                  teamNumber,
                  eventKey,
                  matchKey: finalMatchKey,
                  createdAt: new Date(),
                });
              } catch (err) {

              }
            }
            continue;
          }

          if (!match.predicted_time) continue;

          const minsAway = (match.predicted_time * 1000 - now) / 60000;
          const stage = stageForMinutesAway(minsAway);
          if (!stage) continue;

          const stageMatchKey = `${match.key}::${stage}`;
          const alreadyNotifiedStage = await notifiedMatchesCollection.findOne({
            teamNumber,
            eventKey,
            matchKey: stageMatchKey,
          });
          if (alreadyNotifiedStage) continue;

          let extra = {};
          if (stage === 'alliance') {
            extra = { teammates: allianceTeammates(match, teamKey) };
          } else if (stage === 'queue') {
            extra = { slotLabel: allianceSlotLabel(match, teamKey) };
          } else if (stage === 'matchup') {
            try {
              const oprMap = await getOprMap();
              extra = buildMatchupContext(match, teamKey, oprMap) || {};
            } catch (err) {
              extra = {};
            }
          }

          const { title, body } = notificationForStage(teamNumber, label(match), stage, extra);
          const tagSeed = stageMatchKey;

          let deliveredAnyStage = false;
          for (const sub of groupSubs) {
            if (await sendPushBurst(sub, { title, body, url: '/' }, tagSeed)) {
              sent++;
              deliveredAnyStage = true;
            }
          }
          if (deliveredAnyStage) {
            try {
              await notifiedMatchesCollection.insertOne({
                teamNumber,
                eventKey,
                matchKey: stageMatchKey,
                createdAt: new Date(),
              });
            } catch (err) {

            }
          }
        }
      } catch (err) {

        console.error(`Push check failed for group ${key}:`, err);
      }
    }

    res.json({ checked: groups.size, sent });
  } catch (err) {
    console.error('Push check error:', err);
    res.status(500).json({ error: 'Check failed' });
  }
});

app.get('/event/stats', async (req, res) => {
  const eventKey = cleanString(req.query.eventKey);

  if (eventKey === FAKE_EVENT_KEY) {
    return res.json(fakeEventStats());
  }

  if (!TBA_AUTH_KEY) {
    return res.status(503).json({ error: 'TBA_AUTH_KEY is not configured on the server' });
  }
  if (!eventKey) {
    return res.status(400).json({ error: 'eventKey is required' });
  }

  try {
    const [teams, rankings, oprData] = await Promise.all([
      tbaGet(`/event/${eventKey}/teams/simple`),
      tbaGet(`/event/${eventKey}/rankings`).catch(() => ({ rankings: [] })),
      tbaGetOprs(eventKey),
    ]);
    const names = new Map(teams.map((team) => [team.key, team.nickname || `Team ${team.team_number}`]));
    const rankingByTeam = new Map((rankings.rankings || []).map((ranking) => [ranking.team_key, ranking]));
    const teamKeys = new Set([...names.keys(), ...Object.keys(oprData.oprs || {})]);

    const stats = [...teamKeys].map((teamKey) => {
      const ranking = rankingByTeam.get(teamKey);
      const record = ranking?.record || {};
      const rawOpr = oprData.oprs?.[teamKey];
      return {
        team_number: teamKey.replace(/^frc/, ''),
        name: names.get(teamKey) || `Team ${teamKey.replace(/^frc/, '')}`,
        opr: rawOpr === undefined ? null : Number(rawOpr),
        rank: ranking?.rank ?? 0,
        wins: record.wins || 0,
        losses: record.losses || 0,
        ties: record.ties || 0,
      };
    });
    stats.sort((a, b) => (a.rank || Number.MAX_SAFE_INTEGER) - (b.rank || Number.MAX_SAFE_INTEGER) || (b.opr ?? 0) - (a.opr ?? 0));
    res.json(stats);
  } catch (err) {
    console.error('Event stats error:', err.message);
    res.status(err.status === 404 ? 404 : 500).json({ error: 'Could not load event stats' });
  }
});

const WORLD_RATING_CACHE_MS = 12 * 60 * 60 * 1000;

async function mapWithConcurrency(items, limit, work) {
  const results = [];
  let next = 0;
  async function worker() {
    while (next < items.length) {
      const index = next++;
      try {
        results.push(await work(items[index]));
      } catch (err) {
        console.warn(`World rating skipped ${items[index].key}: ${err.message}`);
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return results;
}

async function rebuildWorldRatings(year) {
  const events = await tbaGet(`/events/${year}/simple`);
  const official = events.filter((event) =>
    [0, 1, 2, 3, 4].includes(event.event_type) && event.end_date &&
    new Date(`${event.end_date}T23:59:59Z`) <= new Date(),
  );
  const eventRows = await mapWithConcurrency(official, 6, async (event) => {
    const [teams, oprData, rankings] = await Promise.all([
      tbaGet(`/event/${event.key}/teams/simple`),
      tbaGetOprs(event.key),
      tbaGet(`/event/${event.key}/rankings`).catch(() => ({ rankings: [] })),
    ]);
    const names = new Map(teams.map((team) => [team.key, team.nickname || `Team ${team.team_number}`]));
    const records = new Map((rankings.rankings || []).map((r) => [r.team_key, r.record || {}]));
    return Object.entries(oprData.oprs || {}).map(([teamKey, rawOpr]) => {
      const record = records.get(teamKey) || {};
      const played = (record.wins || 0) + (record.losses || 0) + (record.ties || 0);
      return { teamKey, name: names.get(teamKey) || `Team ${teamKey.replace(/^frc/, '')}`,
        opr: Number(rawOpr || 0), weight: Math.max(1, played),
        wins: record.wins || 0, losses: record.losses || 0, ties: record.ties || 0 };
    });
  });
  const totals = new Map();
  for (const rows of eventRows) for (const row of rows) {
    const old = totals.get(row.teamKey) || { ...row, weightedOpr: 0, weightTotal: 0, wins: 0, losses: 0, ties: 0 };
    old.name = row.name;
    old.weightedOpr += row.opr * row.weight;
    old.weightTotal += row.weight;
    old.wins += row.wins; old.losses += row.losses; old.ties += row.ties;
    totals.set(row.teamKey, old);
  }
  const teams = [...totals.values()].map((row) => ({
    team_number: row.teamKey.replace(/^frc/, ''), name: row.name,
    opr: Number((row.weightedOpr / row.weightTotal).toFixed(2)),
    wins: row.wins, losses: row.losses, ties: row.ties,
  })).sort((a, b) => b.opr - a.opr);
  teams.forEach((team, index) => { team.rank = index + 1; });
  const doc = { _id: String(year), year, teams, refreshedAt: new Date(), eventCount: official.length };
  await worldRatingsCollection.replaceOne({ _id: doc._id }, doc, { upsert: true });
  return doc;
}

function startWorldRatingRefresh(year) {
  if (!worldRatingRefresh) {
    worldRatingRefresh = rebuildWorldRatings(year)
      .catch((err) => console.error('World rating refresh failed:', err.message))
      .finally(() => { worldRatingRefresh = null; });
  }
  return worldRatingRefresh;
}

app.get('/world/stats', async (req, res) => {
  if (!TBA_AUTH_KEY) return res.status(503).json({ error: 'TBA_AUTH_KEY is not configured on the server' });
  const year = Number(cleanString(req.query.year) || new Date().getFullYear());
  try {
    const cached = await worldRatingsCollection.findOne({ _id: String(year) });
    const stale = !cached || Date.now() - new Date(cached.refreshedAt).getTime() > WORLD_RATING_CACHE_MS;
    if (stale) startWorldRatingRefresh(year);
    if (cached) return res.json({ teams: cached.teams, year, eventCount: cached.eventCount, refreshedAt: cached.refreshedAt, refreshing: stale });
    res.status(202).json({ teams: [], year, refreshing: true, message: 'World rating is being calculated. Try again shortly.' });
  } catch (err) {
    console.error('World stats error:', err.message);
    res.status(500).json({ error: 'Could not load world stats' });
  }
});


app.get('/world/team/:teamNumber', async (req, res) => {
  const year = String(new Date().getFullYear());
  try {
    const cached = await worldRatingsCollection.findOne({ _id: year });
    if (!cached) return res.status(202).json({ error: 'World rating is being calculated' });
    const index = cached.teams.findIndex((team) => team.team_number === req.params.teamNumber);
    if (index < 0) return res.status(404).json({ error: 'Team is not in the current world rating' });
    res.json({ team: cached.teams[index], nearby: cached.teams.slice(Math.max(0, index - 2), index + 4) });
  } catch (err) {
    res.status(500).json({ error: 'Could not load team rating' });
  }
});

app.get('/event/teams', async (req, res) => {
  const eventKey = cleanString(req.query.eventKey);

  if (eventKey === FAKE_EVENT_KEY) {
    return res.json(fakeEventTeamsList());
  }

  if (!TBA_AUTH_KEY) {
    return res.status(503).json({ error: 'TBA_AUTH_KEY is not configured on the server' });
  }
  if (!eventKey) {
    return res.status(400).json({ error: 'eventKey is required' });
  }

  try {
    const cached = await eventTeamsCollection.findOne({ eventKey });
    if (cached && Date.now() - new Date(cached.refreshedAt).getTime() < 6 * 60 * 60 * 1000) {
      return res.json(cached.teams);
    }
    const teams = await tbaGet(`/event/${eventKey}/teams/simple`);
    const mapped = teams
      .map((t) => ({
        team_number: String(t.team_number),
        name: t.nickname || `Team ${t.team_number}`,
      }))
      .sort((a, b) => Number(a.team_number) - Number(b.team_number));
    await eventTeamsCollection.updateOne(
      { eventKey },
      { $set: { teams: mapped, refreshedAt: new Date() } },
      { upsert: true },
    );
    res.json(mapped);
  } catch (err) {
    console.error('Event teams error:', err);
    res.status(err.status === 404 ? 404 : 500).json({ error: 'Could not load event teams' });
  }
});

app.get('/team/profile', async (req, res) => {
  const teamNumber = cleanString(req.query.teamNumber);

  if (isFakeTeamNumber(teamNumber)) {
    return res.json({
      team_name: 'Ridgebotics (test)',
      rookie_year: new Date().getFullYear(),
      world_rank: null,
      events: [],
      awards: [],
    });
  }

  if (!TBA_AUTH_KEY) {
    return res.status(503).json({ error: 'TBA_AUTH_KEY is not configured on the server' });
  }
  if (!teamNumber) {
    return res.status(400).json({ error: 'teamNumber is required' });
  }

  const teamKey = `frc${teamNumber}`;
  try {
    const teamInfo = await tbaGet(`/team/${teamKey}`);
    const [yearsParticipated, awards] = await Promise.all([
      tbaGet(`/team/${teamKey}/years_participated`).catch(() => []),
      tbaGet(`/team/${teamKey}/awards`).catch(() => []),
    ]);


    const perYear = await Promise.all(
      yearsParticipated.map(async (year) => {
        try {
          const [events, statuses] = await Promise.all([
            tbaGet(`/team/${teamKey}/events/${year}/simple`),
            tbaGet(`/team/${teamKey}/events/${year}/statuses`).catch(() => ({})),
          ]);
          return events.map((event) => {
            const status = statuses[event.key];
            const ranking = status?.qual?.ranking;
            return {
              eventKey: event.key,
              eventName: event.name,
              year,
              rank: ranking?.rank ?? null,
              numTeams: status?.qual?.num_teams ?? null,
            };
          });
        } catch (err) {
          return [];
        }
      }),
    );

    const flatEvents = perYear.flat();
    const eventNameByKey = new Map(flatEvents.map((e) => [e.eventKey, e.eventName]));

    const rating = await worldRatingsCollection.findOne({ _id: String(new Date().getFullYear()) });
    const worldRank = rating?.teams?.find((team) => team.team_number === teamNumber)?.rank ?? null;

    res.json({
      team_name: teamInfo.nickname || teamInfo.name || `Team ${teamNumber}`,
      rookie_year: teamInfo.rookie_year || null,
      world_rank: worldRank,
      events: flatEvents.map((e) => ({
        event_key: e.eventKey,
        event_name: e.eventName,
        year: e.year,
        rank: e.rank,
        num_teams: e.numTeams,
        awards: awards.filter((a) => a.event_key === e.eventKey).map((a) => a.name),
      })),
      awards: awards.map((a) => ({
        name: a.name,
        event_name: eventNameByKey.get(a.event_key) || a.event_key,
        year: a.year,
      })).sort((a, b) => b.year - a.year),
    });
  } catch (err) {
    console.error('Team profile error:', err);
    res.status(err.status === 404 ? 404 : 500).json({ error: 'Could not load team profile' });
  }
});

connectToMongo()
  .then(() => {
    app.listen(PORT, () => {
      console.log(`Server running on port ${PORT}`);
    });
  })
  .catch((err) => {
    console.error('Failed to connect to MongoDB:', err);
    process.exit(1);
  });
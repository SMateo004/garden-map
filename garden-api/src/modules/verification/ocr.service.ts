/**
 * OCR service: extract data from CI document using Textract (preferred) or Rekognition DetectText.
 */

import { DetectDocumentTextCommand, TextractClient } from '@aws-sdk/client-textract';
import { DetectTextCommand } from '@aws-sdk/client-rekognition';
import { RekognitionClient } from '@aws-sdk/client-rekognition';
import { env } from '../../config/env.js';
import logger from '../../shared/logger.js';

export interface ExtractedCIData {
  firstName: string | null;
  lastName: string | null;
  fullName: string | null;
  documentNumber: string | null;
  dateOfBirth: string | null;
  rawText: string;
  confidence: number;
  source: 'textract' | 'rekognition';
  hasExplicitLabels?: boolean;
}

function getTextractClient(): TextractClient | null {
  if (env.AWS_ACCESS_KEY_ID && env.AWS_SECRET_ACCESS_KEY) {
    return new TextractClient({
      region: env.AWS_REGION,
      credentials: {
        accessKeyId: env.AWS_ACCESS_KEY_ID,
        secretAccessKey: env.AWS_SECRET_ACCESS_KEY,
      },
    });
  }
  return null;
}

function getRekognitionClient(): RekognitionClient | null {
  if (env.AWS_ACCESS_KEY_ID && env.AWS_SECRET_ACCESS_KEY) {
    return new RekognitionClient({
      region: env.AWS_REGION,
      credentials: {
        accessKeyId: env.AWS_ACCESS_KEY_ID,
        secretAccessKey: env.AWS_SECRET_ACCESS_KEY,
      },
    });
  }
  return null;
}

/** Normalize string for comparison: uppercase, remove accents, trim extra spaces. */
export function normalizeOCRText(s: string): string {
  if (!s) return '';
  return s
    .trim()
    .toUpperCase()
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .replace(/\s+/g, ' ');
}

function normalizeForMatch(s: string): string {
  return normalizeOCRText(s);
}

/** Calculate name similarity (0-100). */
export function getNameSimilarity(str1: string, str2: string): number {
  const s1 = normalizeOCRText(str1);
  const s2 = normalizeOCRText(str2);
  if (s1 === s2) return 100;

  // Simple intersection-based similarity for multi-part names
  const p1 = s1.split(' ').filter((p) => p.length > 2);
  const p2 = s2.split(' ').filter((p) => p.length > 2);
  if (p1.length === 0 || p2.length === 0) return 0;

  let matches = 0;
  for (const part of p1) {
    if (p2.some((o) => o === part || o.includes(part) || part.includes(o))) {
      matches++;
    }
  }
  return Math.round((matches / Math.max(p1.length, p2.length)) * 100);
}

const SPANISH_MONTHS: { [key: string]: string } = {
  enero: '01', febrero: '02', marzo: '03', abril: '04', mayo: '05', junio: '06',
  julio: '07', agosto: '08', septiembre: '09', octubre: '10', noviembre: '11', diciembre: '12'
};

/** Extract CI number pattern (Bolivia: 6-8 digits, often followed by department suffix like LP, SC, etc). */
function extractCINumber(text: string): string | null {
  const normalized = text.toUpperCase();
  const patterns = [
    // Look for patterns like "CI: 1234567" or "C.I. 1234567"
    /(?:CI|CEDULA|DOCUMENTO|NO\.?|C\.I\.)[:\s]*([0-9]{6,8}(?:\s*[A-Z]{2})?)/i,
    // Look for standalone 7-8 digits that might have a suffix
    /\b(\d{7,8}(?:\s*[A-Z]{2})?)\b/,
    /\b(\d{6,8})\b/,
  ];
  for (const re of patterns) {
    const m = normalized.match(re);
    if (m) return (m[1] ?? m[0]).trim();
  }
  return null;
}

function parseSpanishDate(text: string): string | null {
  const normalized = normalizeOCRText(text);
  // Match "FECHA DE NACIMIENTO: 13/04/2004" or "NACIDO EL 13 DE ABRIL DE 2004"
  const reLiteral = /(?:NACIDO\s+EL\s+|FECHA\s+DE\s+NACIMIENTO\s*[:\s]*)(\d{1,2})\s+DE\s+([A-Z]+)\s+DE\s+(\d{4})/i;
  const m = normalized.match(reLiteral);
  if (m && m[1] && m[2] && m[3]) {
    const day = m[1].padStart(2, '0');
    const monthStr = m[2].toLowerCase();
    const month = SPANISH_MONTHS[monthStr];
    const year = m[3];
    if (month) return `${day}/${month}/${year}`;
  }
  return null;
}

/** Check if two names match (fuzzy: contains or normalized equality). */
export function namesMatch(ocrName: string | null, userFullName: string): boolean {
  if (!ocrName || !userFullName) return false;
  const similarity = getNameSimilarity(ocrName, userFullName);
  return similarity >= 90;
}

/** Extract date of birth (DD/MM/YYYY or YYYY-MM-DD). */
function extractDOB(text: string): string | null {
  const spanishDate = parseSpanishDate(text);
  if (spanishDate) return spanishDate;

  const patterns = [
    /\b(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})\b/,
    /\b(\d{4}[\/\-]\d{1,2}[\/\-]\d{1,2})\b/,
    /(?:nacimiento|fecha\s*nac|dob|nacido\s*el)[:\s]*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})/i,
  ];
  for (const re of patterns) {
    const m = text.match(re);
    if (m && m[1]) return m[1].trim();
  }
  return null;
}

/** 
 * Helper to check if a line is a prohibited document label (not a name). 
 */
function isProhibitedName(text: string): boolean {
  const normalized = normalizeOCRText(text);
  const forbidden = [
    'SERVICIO GENERAL',
    'IDENTIFICACION PERSONAL',
    'CERTIFICA',
    'FIRMA',
    'FOTOGRAFIA',
    'IMPRESION PERTENECE',
    'ESTADO PLURINACIONAL',
    'REPUBLICA DE BOLIVIA',
    'CEDULA DE IDENTIDAD',
    'NACIDO EL',
    'FECHA DE NACIMIENTO',
    'EXPIRA EL',
    'EMITIDA EL',
    'DOMICILIO',
    'ESTADO CIVIL',
    'PROFESION',
    'PADRE',
    'MADRE',
    'VALIDEZ',
    'BIO',
    'SERIE',
    'SECCION',
    'PERTENECE',
    'COCHABAMBA',
    'SANTA CRUZ',
    'LA PAZ',
    'CHUQUISACA',
    'TARIJA',
    'POTOSI',
    'ORURO',
    'BENI',
    'PANDO',
    'DOCUMENTOS REGISTRADOS',
    'DOCUMENTOSREGISTRADOS',
    'DEPARTAMENTAL',
    'BARCTCK',
    'CNAL',
    'CERCADO'
  ];
  return forbidden.some(term => normalized.includes(term.toUpperCase()));
}

/** Extract full name - handles front (NOMBRES/APELLIDOS) and back CI models. */
function extractFullName(text: string): { name: string | null; hadLabels: boolean } {
  const normalized = normalizeOCRText(text);
  const lines = text.split(/\r?\n/).map((l) => l.trim()).filter(l => l.length > 2);
  let hadLabels = false;

  // 1. Handle Model: Name on Front (Explicit NOMBRES / APELLIDOS labels)
  // These are prioritized as per official request.
  let foundNombres = '';
  let foundApellidos = '';
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i] || '';
    const normLine = normalizeOCRText(line);

    if (/NOMBRES?[:\s]*/i.test(normLine)) {
      hadLabels = true;
      let val = line.replace(/NOMBRES?[:\s]*/i, '').trim();
      const nextLine = lines[i + 1];
      if (val.length < 3 && nextLine) val = nextLine;

      // Filter out technical codes (noise)
      if (val && (/^[A-Z0-9-]{5,15}$/.test(val) || isProhibitedName(val))) {
        const afterNoise = lines[i + 2];
        if (afterNoise && !isProhibitedName(afterNoise) && !/^[A-Z0-9-]{5,15}$/.test(afterNoise)) {
          val = afterNoise;
        }
      }
      if (val && !isProhibitedName(val) && !/^[A-Z0-9-]{5,15}$/.test(val)) foundNombres = val;
    }
    if (/APELLIDOS?[:\s]*/i.test(normLine)) {
      hadLabels = true;
      let val = line.replace(/APELLIDOS?[:\s]*/i, '').trim();
      const nextLine = lines[i + 1];
      if (val.length < 3 && nextLine) val = nextLine;

      if (val && (/^[A-Z0-9-]{5,15}$/.test(val) || isProhibitedName(val))) {
        const afterNoise = lines[i + 2];
        if (afterNoise && !isProhibitedName(afterNoise) && !/^[A-Z0-9-]{5,15}$/.test(afterNoise)) {
          val = afterNoise;
        }
      }
      if (val && !isProhibitedName(val) && !/^[A-Z0-9-]{5,15}$/.test(val)) foundApellidos = val;
    }
  }

  if (foundNombres && foundApellidos) {
    return { name: `${foundNombres} ${foundApellidos}`, hadLabels };
  }

  // 2. Handle Model: Name on Back (The "e impresión pertenece" model)
  const backModelTriggers = [
    /SERVICI?O GENERAL DE IDENTIFICACI/i,
    /CERTIFICA[:\s]*QUE LA FIRMA/i,
    /E IMPRESI[OÓ]N PERTENECE/i
  ];

  let triggerLineIdx = -1;
  for (let i = 0; i < lines.length; i++) {
    const normLine = normalizeOCRText(lines[i] || '');
    if (backModelTriggers.some(rgx => rgx.test(normLine))) {
      triggerLineIdx = i;
      break;
    }
  }

  if (triggerLineIdx !== -1) {
    for (let j = triggerLineIdx + 1; j <= triggerLineIdx + 6 && j < lines.length; j++) {
      const candidate = lines[j];
      if (!candidate) continue;
      if (candidate.length > 8 && !/\d/.test(candidate) && !isProhibitedName(candidate)) {
        return { name: candidate, hadLabels: false };
      }
    }
  }

  // 3. Handle Model: Name on Back (Label "A: ")
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i] || '';
    const normLine = normalizeOCRText(line);
    if (normLine === 'A' || normLine === 'A:' || normLine.startsWith('A ')) {
      let candidate = line.replace(/^A[:\s]*/i, '').trim();
      if (candidate.length > 5 && !/\d/.test(candidate) && !isProhibitedName(candidate)) {
        return { name: candidate, hadLabels: false };
      }
      if (i > 0) {
        const prev = lines[i - 1];
        if (prev && prev.length > 8 && !/\d/.test(prev) && !isProhibitedName(prev)) {
          return { name: prev, hadLabels: false };
        }
      }
    }
  }

  // 4. Last resort
  if (foundNombres && foundNombres.length > 8) return { name: foundNombres, hadLabels };
  if (foundApellidos && foundApellidos.length > 8) return { name: foundApellidos, hadLabels };

  const candidateLines = lines.filter(l =>
    l.length > 10 && !/\d/.test(l) && !isProhibitedName(l)
  );

  return { name: candidateLines.length > 0 ? (candidateLines[0] || null) : null, hadLabels: false };
}

async function extractWithTextract(image: Buffer): Promise<{ text: string; confidence: number } | null> {
  const client = getTextractClient();
  if (!client) return null;

  const command = new DetectDocumentTextCommand({
    Document: { Bytes: image },
  });
  const response = await client.send(command);
  const blocks = response.Blocks ?? [];
  const lines: string[] = [];
  let totalConf = 0;
  let count = 0;
  for (const b of blocks) {
    if (b.BlockType === 'LINE' && b.Text) {
      lines.push(b.Text);
      if (b.Confidence != null) {
        totalConf += b.Confidence;
        count++;
      }
    }
  }
  const text = lines.join('\n');
  const confidence = count > 0 ? totalConf / count : 0;
  return { text, confidence };
}

async function extractWithRekognition(image: Buffer): Promise<{ text: string; confidence: number } | null> {
  const client = getRekognitionClient();
  if (!client) return null;

  const command = new DetectTextCommand({
    Image: { Bytes: image },
  });
  const response = await client.send(command);
  const detections = response.TextDetections ?? [];
  const lines: string[] = [];
  let totalConf = 0;
  let count = 0;
  for (const d of detections) {
    if (d.Type === 'LINE' && d.DetectedText) {
      lines.push(d.DetectedText);
      if (d.Confidence != null) {
        totalConf += d.Confidence;
        count++;
      }
    }
  }
  const text = lines.join('\n');
  const confidence = count > 0 ? totalConf / count : 0;
  return { text, confidence };
}

/**
 * Extract CI data from document image.
 * Uses Textract first, falls back to Rekognition DetectText.
 */
export async function extractCIData(image: Buffer): Promise<ExtractedCIData> {
  let result: { text: string; confidence: number } | null = null;
  let source: 'textract' | 'rekognition' = 'textract';

  try {
    result = await extractWithTextract(image);
  } catch (err) {
    logger.warn('Textract failed, falling back to Rekognition', { error: err instanceof Error ? err.message : err });
  }

  if (!result || result.text.length < 10) {
    try {
      result = await extractWithRekognition(image);
      source = 'rekognition';
    } catch (err) {
      logger.error('Rekognition OCR also failed', { error: err instanceof Error ? err.message : err });
    }
  }

  if (!result) {
    if (!getTextractClient() && !getRekognitionClient()) {
      logger.warn('Rekognition/Textract: AWS not configured, returning mock OCR data');
      return {
        firstName: 'MOCK',
        lastName: 'USER',
        fullName: 'MOCK USER',
        documentNumber: Math.floor(1000000 + Math.random() * 9000000).toString(),
        dateOfBirth: '01/01/1990',
        rawText: 'MOCK DOCUMENT TEXT',
        confidence: 0.95,
        source: 'rekognition',
        hasExplicitLabels: true,
      };
    }
    return {
      firstName: null,
      lastName: null,
      fullName: null,
      documentNumber: null,
      dateOfBirth: null,
      rawText: '',
      confidence: 0,
      source: 'rekognition',
      hasExplicitLabels: false,
    };
  }

  const { name: fullNameRaw, hadLabels } = extractFullName(result.text);
  const documentNumber = extractCINumber(result.text);
  const dateOfBirth = extractDOB(result.text);

  // Basic split for first/last name if not explicitly found
  const names = (fullNameRaw || '').split(' ');
  const firstName = names[0] || null;
  const lastName = names.slice(1).join(' ') || null;

  return {
    firstName: firstName ? normalizeOCRText(firstName) : null,
    lastName: lastName ? normalizeOCRText(lastName) : null,
    fullName: fullNameRaw ? normalizeOCRText(fullNameRaw) : null,
    documentNumber: documentNumber ? normalizeOCRText(documentNumber) : null,
    dateOfBirth: dateOfBirth ? normalizeOCRText(dateOfBirth) : null,
    rawText: result.text,
    confidence: result.confidence,
    source,
    hasExplicitLabels: hadLabels,
  };
}

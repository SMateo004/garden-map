import jwt from 'jsonwebtoken';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, 'garden-api', '.env') });

const secret = process.env.JWT_SECRET || 'secret';
const token = jwt.sign(
  { userId: 'c78ef370-7110-47bb-b770-6e03ec00694b', role: 'CAREGIVER', id: 'c78ef370-7110-47bb-b770-6e03ec00694b' },
  secret,
  { expiresIn: '30d' }
);
console.log(token);

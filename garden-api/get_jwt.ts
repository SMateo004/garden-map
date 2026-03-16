import { generateToken } from './src/utils/jwt';
console.log(generateToken({ id: 'admin1', rol: 'ADMIN' }));

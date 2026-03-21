console.log('Test loading socket.service...');
import('./src/services/socket.service.js').then(() => {
  console.log('Done!');
  process.exit(0);
}).catch(err => {
  console.error(err);
  process.exit(1);
});

import axios from 'axios';
import FormData from 'form-data';
import fs from 'fs';

async function testUpload() {
    const formData = new FormData();
    // Create dummy buffers
    const dummy = Buffer.from('fake image data');
    for (let i = 0; i < 2; i++) {
        formData.append('photos', dummy, { filename: `test${i}.jpg`, contentType: 'image/jpeg' });
    }

    try {
        const res = await axios.post('http://localhost:3000/api/upload/registration-photos', formData, {
            headers: formData.getHeaders(),
        });
        console.log('Success:', JSON.stringify(res.data, null, 2));
    } catch (err: any) {
        if (err.response) {
            console.log('Error:', err.response.status, JSON.stringify(err.response.data, null, 2));
        } else {
            console.log('Error:', err.message);
        }
    }
}

testUpload();

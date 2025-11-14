const express = require('express');
const axios = require('axios');

const app = express();
app.use(express.static('public'));
app.use(express.json());

// use ECS Service Connect DNS from environment variable
const SERVER_URL = process.env.VOTE_SERVER_URL;

if (!SERVER_URL) {
  console.error("ERROR: VOTE_SERVER_URL is not set");
}

app.post('/vote', async (req, res) => {
  try {
    const response = await axios.post(`${SERVER_URL}/vote`, req.body);
    res.status(response.status).json(response.data);
  } catch (err) {
    console.error("Vote request failed:", err.message);
    res.status(err.response?.status || 500).json(err.response?.data || { error: 'Internal server error' });
  }
});

app.get('/results', async (req, res) => {
  try {
    const response = await axios.get(`${SERVER_URL}/results`);
    res.status(response.status).json(response.data);
  } catch (err) {
    console.error("Results request failed:", err.message);
    res.status(err.response?.status || 500).json(err.response?.data || { error: 'Internal server error' });
  }
});

app.listen(3000, () => {
  console.log('Client is running on port 3000');
});

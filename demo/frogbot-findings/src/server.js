// DEMO ONLY - intentionally vulnerable code to trigger SAST and CVE contextual analysis.
const crypto = require('crypto');
const { exec } = require('child_process');
const fs = require('fs');
const express = require('express');
const _ = require('lodash');
const minimist = require('minimist');
const jwt = require('jsonwebtoken');
const axios = require('axios');
const config = require('./config');

const app = express();
app.use(express.json());
const args = minimist(process.argv.slice(2)); // CVE-2021-44906 (prototype pollution)

// SAST: OS command injection
app.get('/ping', (req, res) => {
  exec(`ping -c 1 ${req.query.host}`, (err, out) => res.send(out));
});

// SAST: eval of user input (code injection)
app.get('/calc', (req, res) => res.send(String(eval(req.query.expr))));

// SAST: path traversal
app.get('/file', (req, res) => res.send(fs.readFileSync(`./public/${req.query.name}`, 'utf8')));

// SAST: reflected XSS
app.get('/hello', (req, res) => res.send(`<h1>Hello ${req.query.name}</h1>`));

// SAST: SQL injection (string concatenation)
app.get('/user', (req, res) => {
  const query = "SELECT * FROM users WHERE id = '" + req.query.id + "'";
  res.send(query);
});

// SAST: open redirect
app.get('/go', (req, res) => res.redirect(req.query.url));

// SAST: SSRF
app.get('/proxy', async (req, res) => res.send((await axios.get(req.query.url)).data));

// SAST: weak hash
app.post('/hash', (req, res) =>
  res.send(crypto.createHash('md5').update(req.body.password).digest('hex')));

// CVE-2020-8203 / CVE-2020-28500 / CVE-2021-23337 (lodash) - applicable: vulnerable functions are called
app.post('/merge', (req, res) => res.json(_.merge({}, req.body)));
app.post('/tpl', (req, res) => res.send(_.template(req.body.tpl)({})));
app.post('/zipobj', (req, res) => res.json(_.zipObjectDeep([req.body.path], [1])));

// SAST: hardcoded secret used for signing + insecure cookie
app.post('/login', (req, res) => {
  const token = jwt.sign({ user: req.body.user }, config.jwtSecret);
  res.cookie('session', token, { httpOnly: false, secure: false });
  res.json({ token });
});

app.listen(process.env.PORT || 3999);

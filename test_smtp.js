const nodemailer = require('nodemailer');
const t = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'smtp-relay.brevo.com',
  port: 587,
  secure: false,
  auth: { user: process.env.SMTP_USER || '', pass: process.env.SMTP_PASS || '' }
});
t.sendMail({
  from: 'kripaverma410@gmail.com',
  to: 'kripaverma410@gmail.com',
  subject: 'MediaBot SMTP Test',
  text: 'If you get this, SMTP is working!'
}, (err, info) => {
  if (err) console.log('ERROR:', err.message);
  else console.log('SUCCESS:', info.response, '\nMessageId:', info.messageId, '\nAccepted:', info.accepted, '\nRejected:', info.rejected);
  process.exit();
});

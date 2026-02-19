/**
 * Download Route
 * Maps POST /api/download to the controller.
 */

const express = require("express");
const router = express.Router();
const { handleDownload } = require("../controllers/downloadController");

// POST /api/download – accepts { url } and returns an MP3 file
router.post("/", handleDownload);

module.exports = router;

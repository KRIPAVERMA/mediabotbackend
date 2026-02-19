/**
 * Download Routes — Async Job-Based
 *
 *   POST /api/download         → start job, returns { jobId }
 *   GET  /api/download/:id     → poll status { status, progress, error }
 *   GET  /api/download/:id/file → download the finished file
 */

const express = require("express");
const router = express.Router();
const { handleDownload, getJobStatus, getJobFile, debugJobs } = require("../controllers/downloadController");

router.post("/", handleDownload);
router.get("/debug/jobs", debugJobs);   // MUST be before /:id
router.get("/:id", getJobStatus);
router.get("/:id/file", getJobFile);

module.exports = router;

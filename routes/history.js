/**
 * History Routes – /api/history
 *   GET  /           → get user's download history (protected)
 *   GET  /stats      → get download stats (protected)
 *   DELETE /:id      → delete a history entry (protected)
 */

const express = require("express");
const router = express.Router();
const db = require("../db/database");
const { authMiddleware } = require("../middleware/auth");

// All routes require auth
router.use(authMiddleware);

// ── GET /api/history ───────────────────────────────────────
router.get("/", (req, res) => {
  try {
    const page = Math.max(1, parseInt(req.query.page) || 1);
    const limit = Math.min(50, Math.max(1, parseInt(req.query.limit) || 20));
    const offset = (page - 1) * limit;

    const rows = db.prepare(`
      SELECT id, url, mode, platform, format, filename, status, created_at
      FROM download_history
      WHERE user_id = ?
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?
    `).all(req.userId, limit, offset);

    // Append 'Z' to created_at timestamps to mark them as UTC
    const history = rows.map(row => ({
      ...row,
      created_at: row.created_at ? row.created_at + 'Z' : row.created_at
    }));

    const total = db.prepare(
      "SELECT COUNT(*) as count FROM download_history WHERE user_id = ?"
    ).get(req.userId).count;

    res.json({
      history,
      pagination: { page, limit, total, pages: Math.ceil(total / limit) },
    });
  } catch (err) {
    console.error("History fetch error:", err);
    res.status(500).json({ error: "Failed to fetch history." });
  }
});

// ── GET /api/history/stats ─────────────────────────────────
router.get("/stats", (req, res) => {
  try {
    const stats = db.prepare(`
      SELECT
        COUNT(*)                                        as totalDownloads,
        COUNT(CASE WHEN format = 'MP3' THEN 1 END)     as audioDownloads,
        COUNT(CASE WHEN format = 'MP4' THEN 1 END)     as videoDownloads,
        COUNT(CASE WHEN platform = 'YouTube' THEN 1 END)   as youtube,
        COUNT(CASE WHEN platform = 'Instagram' THEN 1 END) as instagram,
        COUNT(CASE WHEN platform = 'Facebook' THEN 1 END)  as facebook
      FROM download_history
      WHERE user_id = ?
    `).get(req.userId);

    res.json({ stats });
  } catch (err) {
    console.error("Stats error:", err);
    res.status(500).json({ error: "Failed to fetch stats." });
  }
});

// ── DELETE /api/history/:id ────────────────────────────────
router.delete("/:id", (req, res) => {
  try {
    const result = db.prepare(
      "DELETE FROM download_history WHERE id = ? AND user_id = ?"
    ).run(req.params.id, req.userId);

    if (result.changes === 0) {
      return res.status(404).json({ error: "History entry not found." });
    }
    res.json({ message: "Deleted." });
  } catch (err) {
    console.error("Delete error:", err);
    res.status(500).json({ error: "Failed to delete." });
  }
});

module.exports = router;

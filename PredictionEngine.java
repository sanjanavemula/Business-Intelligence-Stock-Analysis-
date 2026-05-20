package com.stockstream.dashboard;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.List;
import java.util.Map;

/**
 * REST + page controller for the StockStream dashboard.
 * All REST endpoints are under /api/
 */
@Controller
public class StockController {

    @Autowired private StockRepository repo;
    @Autowired private WebSocketBroadcaster broadcaster;

    // ── Serve HTML page ────────────────────────────────────────────────────────
    @GetMapping("/")
    public String index() {
        return "index";   // resolves to templates/index.html via Thymeleaf
    }

    // ── GET /api/latest ────────────────────────────────────────────────────────
    @GetMapping("/api/latest")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> getLatest() {
        try {
            List<StockLatest> data = repo.findAllLatest();
            return ResponseEntity.ok(Map.of(
                "data", data,
                "ts",   Instant.now().toString()
            ));
        } catch (Exception e) {
            return ResponseEntity.ok(Map.of("data", List.of(), "error", e.getMessage()));
        }
    }

    // ── GET /api/history/{symbol}?limit=60 ────────────────────────────────────
    @GetMapping("/api/history/{symbol}")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> getHistory(
            @PathVariable String symbol,
            @RequestParam(defaultValue = "60") int limit) {
        try {
            var data = repo.findPriceHistory(symbol, limit);
            // Reverse so oldest first (chronological for chart)
            java.util.Collections.reverse(data);
            return ResponseEntity.ok(Map.of(
                "symbol", symbol.toUpperCase(),
                "data",   data
            ));
        } catch (Exception e) {
            return ResponseEntity.ok(Map.of("symbol", symbol, "data", List.of()));
        }
    }

    // ── GET /api/analytics/{symbol} ───────────────────────────────────────────
    @GetMapping("/api/analytics/{symbol}")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> getAnalytics(@PathVariable String symbol) {
        try {
            var data = repo.findLatestAnalytics(symbol);
            return ResponseEntity.ok(Map.of("symbol", symbol.toUpperCase(), "data", data));
        } catch (Exception e) {
            return ResponseEntity.ok(Map.of("symbol", symbol, "data", Map.of()));
        }
    }

    // ── GET /api/stats ─────────────────────────────────────────────────────────
    @GetMapping("/api/stats")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> getStats() {
        try {
            return ResponseEntity.ok(repo.getPipelineStats());
        } catch (Exception e) {
            return ResponseEntity.ok(Map.of("error", e.getMessage()));
        }
    }

    // ── GET /api/volatility ────────────────────────────────────────────────────
    @GetMapping("/api/volatility")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> getVolatility() {
        try {
            return ResponseEntity.ok(Map.of("data", repo.getVolatilityRanking()));
        } catch (Exception e) {
            return ResponseEntity.ok(Map.of("data", List.of()));
        }
    }
}

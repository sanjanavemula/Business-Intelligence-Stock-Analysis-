package com.stockstream.dashboard;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.BeanPropertyRowMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Map;

/**
 * All database queries for the dashboard API.
 */
@Repository
public class StockRepository {

    @Autowired
    private JdbcTemplate jdbc;

    // ── Latest snapshots for all tickers ──────────────────────────────────────
    public List<StockLatest> findAllLatest() {
        return jdbc.query(
            "SELECT symbol, price, open_price, high_price, low_price, " +
            "       ma5, ma20, volatility, trend, change_pct, volume, " +
            "       DATE_FORMAT(updated_at, '%Y-%m-%dT%H:%i:%sZ') AS updated_at " +
            "FROM stock_latest ORDER BY symbol",
            new BeanPropertyRowMapper<>(StockLatest.class)
        );
    }

    // ── Price history for a specific symbol ───────────────────────────────────
    public List<Map<String, Object>> findPriceHistory(String symbol, int limit) {
        return jdbc.queryForList(
            "SELECT price, DATE_FORMAT(timestamp, '%Y-%m-%dT%H:%i:%sZ') AS timestamp " +
            "FROM stock_ticks WHERE symbol = ? " +
            "ORDER BY timestamp DESC LIMIT ?",
            symbol.toUpperCase(), limit
        );
    }

    // ── Latest analytics record for a symbol ─────────────────────────────────
    public Map<String, Object> findLatestAnalytics(String symbol) {
        List<Map<String, Object>> rows = jdbc.queryForList(
            "SELECT symbol, ma5, ma20, volatility, trend, avg_price, " +
            "       min_price, max_price, tick_count, " +
            "       DATE_FORMAT(window_start, '%Y-%m-%dT%H:%i:%sZ') AS window_start, " +
            "       DATE_FORMAT(window_end,   '%Y-%m-%dT%H:%i:%sZ') AS window_end " +
            "FROM stock_analytics WHERE symbol = ? " +
            "ORDER BY window_start DESC LIMIT 1",
            symbol.toUpperCase()
        );
        return rows.isEmpty() ? Map.of() : rows.get(0);
    }

    // ── Pipeline stats ────────────────────────────────────────────────────────
    public Map<String, Object> getPipelineStats() {
        long totalTicks = jdbc.queryForObject(
            "SELECT COUNT(*) FROM stock_ticks", Long.class);
        long totalAnalytics = jdbc.queryForObject(
            "SELECT COUNT(*) FROM stock_analytics", Long.class);
        String lastTick = jdbc.queryForObject(
            "SELECT DATE_FORMAT(MAX(ingested_at), '%Y-%m-%dT%H:%i:%sZ') FROM stock_ticks",
            String.class);
        long activeSymbols = jdbc.queryForObject(
            "SELECT COUNT(DISTINCT symbol) FROM stock_latest", Long.class);

        return Map.of(
            "total_ticks",      totalTicks,
            "total_analytics",  totalAnalytics,
            "last_tick",        lastTick != null ? lastTick : "N/A",
            "active_symbols",   activeSymbols
        );
    }

    // ── Volatility ranking ────────────────────────────────────────────────────
    public List<Map<String, Object>> getVolatilityRanking() {
        return jdbc.queryForList(
            "SELECT symbol, volatility, trend FROM stock_latest " +
            "ORDER BY volatility DESC"
        );
    }
}

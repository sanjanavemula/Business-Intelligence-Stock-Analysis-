package com.stockstream.prediction;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.sql.*;
import java.util.ArrayList;
import java.util.List;

public class PredictionRepository {

    private static final Logger log = LoggerFactory.getLogger(PredictionRepository.class);
    private static final String JDBC_URL =
        "jdbc:mysql://localhost:3306/stockstream_ai?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC";
    private static final String DB_USER = "stockuser";
    private static final String DB_PASS = "StockPass@123";

    static {
        try { Class.forName("com.mysql.cj.jdbc.Driver"); }
        catch (ClassNotFoundException e) { throw new RuntimeException("MySQL driver not found", e); }
    }

    private Connection getConn() throws SQLException {
        return DriverManager.getConnection(JDBC_URL, DB_USER, DB_PASS);
    }

    public void createTableIfNotExists() {
        // Extended table with dual-model columns
        String sql =
            "CREATE TABLE IF NOT EXISTS stock_predictions (" +
            "id BIGINT AUTO_INCREMENT PRIMARY KEY," +
            "symbol VARCHAR(10) NOT NULL," +
            "current_price DECIMAL(12,4) NOT NULL," +
            "predicted_price DECIMAL(12,4) NOT NULL," +
            "price_change DECIMAL(12,4)," +
            "price_change_pct DECIMAL(8,4)," +
            "confidence DECIMAL(5,4)," +
            "trade_signal VARCHAR(10)," +
            "rmse DECIMAL(12,6)," +
            "data_points INT," +
            "model_used VARCHAR(30)," +
            "lr_predicted_price DECIMAL(12,4)," +
            "rf_predicted_price DECIMAL(12,4)," +
            "lr_rmse DECIMAL(12,6)," +
            "rf_rmse DECIMAL(12,6)," +
            "predicted_at DATETIME(3) NOT NULL," +
            "INDEX idx_symbol_time (symbol, predicted_at)) ENGINE=InnoDB";
        try (Connection c = getConn(); Statement s = c.createStatement()) {
            s.executeUpdate(sql);
            // Add new columns if upgrading from old table
            addColumnIfMissing(c, "model_used",          "VARCHAR(30)");
            addColumnIfMissing(c, "lr_predicted_price",  "DECIMAL(12,4)");
            addColumnIfMissing(c, "rf_predicted_price",  "DECIMAL(12,4)");
            addColumnIfMissing(c, "lr_rmse",             "DECIMAL(12,6)");
            addColumnIfMissing(c, "rf_rmse",             "DECIMAL(12,6)");
            log.info("stock_predictions table ready (dual-model schema)");
        } catch (SQLException e) { log.error("createTable error: {}", e.getMessage()); }
    }

    private void addColumnIfMissing(Connection c, String col, String type) {
        try (Statement s = c.createStatement()) {
            s.executeUpdate("ALTER TABLE stock_predictions ADD COLUMN IF NOT EXISTS " + col + " " + type);
        } catch (SQLException e) {
            // Ignore — column already exists in older MySQL versions
        }
    }

    public List<Double> getPriceHistory(String symbol, int n) {
        List<Double> prices = new ArrayList<>();
        try (Connection c = getConn();
             PreparedStatement ps = c.prepareStatement(
                 "SELECT price FROM stock_ticks WHERE symbol=? ORDER BY timestamp DESC LIMIT ?")) {
            ps.setString(1, symbol); ps.setInt(2, n);
            ResultSet rs = ps.executeQuery();
            while (rs.next()) prices.add(rs.getDouble("price"));
        } catch (SQLException e) { log.error("getPriceHistory error: {}", e.getMessage()); }
        return prices;
    }

    public List<String> getAllSymbols() {
        List<String> syms = new ArrayList<>();
        try (Connection c = getConn(); Statement s = c.createStatement();
             ResultSet rs = s.executeQuery("SELECT symbol FROM stock_latest ORDER BY symbol")) {
            while (rs.next()) syms.add(rs.getString("symbol"));
        } catch (SQLException e) { log.error("getAllSymbols error: {}", e.getMessage()); }
        return syms;
    }

    public void savePrediction(StockPrediction p) {
        String sql =
            "INSERT INTO stock_predictions " +
            "(symbol,current_price,predicted_price,price_change,price_change_pct," +
            "confidence,trade_signal,rmse,data_points,model_used," +
            "lr_predicted_price,rf_predicted_price,lr_rmse,rf_rmse,predicted_at) " +
            "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)";
        try (Connection c = getConn(); PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setString(1,  p.getSymbol());
            ps.setDouble(2,  p.getCurrentPrice());
            ps.setDouble(3,  p.getPredictedPrice());
            ps.setDouble(4,  p.getPriceChange());
            ps.setDouble(5,  p.getPriceChangePct());
            ps.setDouble(6,  p.getConfidence());
            ps.setString(7,  p.getSignal());
            ps.setDouble(8,  p.getRmse());
            ps.setInt(9,     p.getDataPoints());
            ps.setString(10, p.getModelUsed());
            ps.setDouble(11, p.getLrPredictedPrice());
            ps.setDouble(12, p.getRfPredictedPrice());
            ps.setDouble(13, p.getLrRmse());
            ps.setDouble(14, p.getRfRmse());
            ps.setString(15, p.getPredictedAt());
            ps.executeUpdate();
            log.info("Saved: {}", p);
        } catch (SQLException e) { log.error("savePrediction error: {}", e.getMessage()); }
    }
}

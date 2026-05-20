package com.stockstream.dashboard;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.sql.*;
import java.util.*;

@RestController
@RequestMapping("/api/predictions")
public class PredictionController {

    private static final String JDBC_URL =
        "jdbc:mysql://localhost:3306/stockstream_ai?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC";
    private static final String DB_USER = "stockuser";
    private static final String DB_PASS = "StockPass@123";

    static {
        try { Class.forName("com.mysql.cj.jdbc.Driver"); }
        catch (ClassNotFoundException e) { throw new RuntimeException(e); }
    }

    private Connection getConn() throws SQLException {
        return DriverManager.getConnection(JDBC_URL, DB_USER, DB_PASS);
    }

    @GetMapping
    public ResponseEntity<Map<String,Object>> getAll() {
        List<Map<String,Object>> result = new ArrayList<>();
        String sql = "SELECT symbol, current_price, predicted_price, price_change, " +
                     "price_change_pct, confidence, trade_signal, rmse, data_points, " +
                     "model_used, lr_predicted_price, rf_predicted_price, lr_rmse, rf_rmse, " +
                     "CAST(predicted_at AS CHAR) AS predicted_at " +
                     "FROM stock_predictions WHERE id IN " +
                     "(SELECT MAX(id) FROM stock_predictions GROUP BY symbol) " +
                     "ORDER BY symbol";
        try (Connection c = getConn();
             Statement s = c.createStatement();
             ResultSet rs = s.executeQuery(sql)) {
            ResultSetMetaData md = rs.getMetaData();
            int cols = md.getColumnCount();
            while (rs.next()) {
                Map<String,Object> row = new LinkedHashMap<>();
                for (int i = 1; i <= cols; i++)
                    row.put(md.getColumnLabel(i), rs.getObject(i));
                result.add(row);
            }
            return ResponseEntity.ok(Map.of("data", result));
        } catch (Exception e) {
            return ResponseEntity.ok(Map.of("data", List.of(), "error", e.getMessage()));
        }
    }

    @GetMapping("/{symbol}")
    public ResponseEntity<Map<String,Object>> getOne(@PathVariable String symbol) {
        String sql = "SELECT symbol, current_price, predicted_price, price_change, " +
                     "price_change_pct, confidence, trade_signal, rmse, data_points, " +
                     "model_used, lr_predicted_price, rf_predicted_price, lr_rmse, rf_rmse, " +
                     "CAST(predicted_at AS CHAR) AS predicted_at " +
                     "FROM stock_predictions WHERE symbol = ? ORDER BY id DESC LIMIT 1";
        try (Connection c = getConn(); PreparedStatement ps = c.prepareStatement(sql)) {
            ps.setString(1, symbol.toUpperCase());
            ResultSet rs = ps.executeQuery();
            ResultSetMetaData md = rs.getMetaData();
            int cols = md.getColumnCount();
            Map<String,Object> row = new LinkedHashMap<>();
            if (rs.next())
                for (int i = 1; i <= cols; i++)
                    row.put(md.getColumnLabel(i), rs.getObject(i));
            return ResponseEntity.ok(Map.of("symbol", symbol.toUpperCase(), "data", row));
        } catch (Exception e) {
            return ResponseEntity.ok(Map.of("symbol", symbol, "data", Map.of(), "error", e.getMessage()));
        }
    }
}

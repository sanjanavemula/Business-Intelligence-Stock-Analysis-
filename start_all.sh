package com.stockstream.prediction;

import org.apache.spark.ml.feature.StandardScaler;
import org.apache.spark.ml.feature.StandardScalerModel;
import org.apache.spark.ml.feature.VectorAssembler;
import org.apache.spark.ml.regression.LinearRegression;
import org.apache.spark.ml.regression.LinearRegressionModel;
import org.apache.spark.ml.regression.RandomForestRegressionModel;
import org.apache.spark.ml.regression.RandomForestRegressor;
import org.apache.spark.sql.*;
import org.apache.spark.sql.types.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * StockStream AI — Dual Model Prediction Engine
 *
 * Trains TWO models per symbol each cycle:
 *   1. Linear Regression  (L-BFGS, StandardScaled)
 *   2. Random Forest Regression (100 trees, no scaling needed)
 *
 * The model with the lower RMSE on training data wins and its
 * prediction is used for the BUY/HOLD/SELL signal. Both predictions
 * are stored in MySQL for comparison in Power BI / dashboard.
 *
 * Run:
 *   spark-submit --class com.stockstream.prediction.PredictionEngine ^
 *     --master local[*] target\prediction-engine.jar
 */
public class PredictionEngine {

    private static final Logger log = LoggerFactory.getLogger(PredictionEngine.class);
    private static final int MIN_DATA = 10;
    private static final int MAX_DATA = 100;
    private static final int LAGS     = 5;
    private static final int INTERVAL = 60000;

    private static final DateTimeFormatter FMT =
        DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS").withZone(ZoneOffset.UTC);

    private final PredictionRepository repo = new PredictionRepository();

    private SparkSession buildSpark() {
        return SparkSession.builder()
            .appName("StockStreamAI-DualModel")
            .config("spark.sql.shuffle.partitions", "2")
            .config("spark.master", "local[*]")
            .getOrCreate();
    }

    private boolean isValid(double v) {
        return !Double.isNaN(v) && !Double.isInfinite(v) && v > 0;
    }

    private boolean pricesAreUsable(Double[] prices) {
        double first = prices[0];
        boolean allSame = true;
        for (Double p : prices) {
            if (!isValid(p)) return false;
            if (p != first) allSame = false;
        }
        if (allSame) {
            log.warn("All prices identical ({}), skipping", first);
            return false;
        }
        return true;
    }

    // ── Result holder for a single model's output ─────────────────────────────
    private static class ModelResult {
        final double predicted;
        final double rmse;
        ModelResult(double predicted, double rmse) {
            this.predicted = predicted;
            this.rmse      = rmse;
        }
    }

    // ── Build feature rows from price history ─────────────────────────────────
    private List<Row> buildRows(Double[] prices) {
        int n = prices.length;
        List<Row> rows = new ArrayList<>();
        for (int i = LAGS; i < n - 1; i++) {
            double l1 = prices[i-1], l2 = prices[i-2], l3 = prices[i-3],
                   l4 = prices[i-4], l5 = prices[i-5];
            double ma5 = (l1+l2+l3+l4+l5) / 5.0;
            double mom = l1 - l2;
            if (!isValid(l1)||!isValid(l2)||!isValid(l3)||
                !isValid(l4)||!isValid(l5)||!isValid(ma5)) continue;
            rows.add(RowFactory.create(l1, l2, l3, l4, l5, ma5, mom, prices[i]));
        }
        return rows;
    }

    private StructType buildSchema() {
        return new StructType(new StructField[]{
            new StructField("lag1",     DataTypes.DoubleType, false, Metadata.empty()),
            new StructField("lag2",     DataTypes.DoubleType, false, Metadata.empty()),
            new StructField("lag3",     DataTypes.DoubleType, false, Metadata.empty()),
            new StructField("lag4",     DataTypes.DoubleType, false, Metadata.empty()),
            new StructField("lag5",     DataTypes.DoubleType, false, Metadata.empty()),
            new StructField("ma5",      DataTypes.DoubleType, false, Metadata.empty()),
            new StructField("momentum", DataTypes.DoubleType, false, Metadata.empty()),
            new StructField("label",    DataTypes.DoubleType, false, Metadata.empty()),
        });
    }

    // ── Model 1: Linear Regression ────────────────────────────────────────────
    private ModelResult runLinearRegression(SparkSession spark,
                                            Dataset<Row> assembled,
                                            Dataset<Row> predRaw,
                                            VectorAssembler va,
                                            StructType schema) {
        StandardScalerModel scaler = new StandardScaler()
            .setInputCol("raw_features").setOutputCol("features")
            .setWithStd(true).setWithMean(true)
            .fit(assembled);
        Dataset<Row> scaled = scaler.transform(assembled);

        LinearRegressionModel lrModel = new LinearRegression()
            .setMaxIter(50).setRegParam(0.3).setElasticNetParam(0.5)
            .setTol(1e-4).setSolver("l-bfgs")
            .setLabelCol("label").setFeaturesCol("features")
            .fit(scaled);

        double rmse = lrModel.summary().rootMeanSquaredError();
        Dataset<Row> predScaled = scaler.transform(va.transform(predRaw));
        double predicted = lrModel.transform(predScaled)
            .select("prediction").first().getDouble(0);

        return new ModelResult(predicted, rmse);
    }

    // ── Model 2: Random Forest Regression ────────────────────────────────────
    // Random Forest doesn't need scaling — it's tree-based and scale-invariant
    private ModelResult runRandomForest(SparkSession spark,
                                        Dataset<Row> assembled,
                                        Dataset<Row> predRaw,
                                        VectorAssembler va) {
        // Rename raw_features to features for RF (no scaling step)
        VectorAssembler vaRF = new VectorAssembler()
            .setInputCols(new String[]{"lag1","lag2","lag3","lag4","lag5","ma5","momentum"})
            .setOutputCol("features");
        Dataset<Row> rfData = vaRF.transform(assembled.drop("raw_features", "features"));

        RandomForestRegressionModel rfModel = new RandomForestRegressor()
            .setNumTrees(50)           // 50 trees — good balance of accuracy vs speed
            .setMaxDepth(5)            // prevent overfitting on small datasets
            .setMinInstancesPerNode(2) // each leaf needs at least 2 samples
            .setFeatureSubsetStrategy("auto")
            .setLabelCol("label").setFeaturesCol("features")
            .fit(rfData);

        // Compute training RMSE manually
        Dataset<Row> trainPreds = rfModel.transform(rfData);
        double mse = trainPreds.selectExpr(
            "avg(pow(label - prediction, 2)) as mse")
            .first().getDouble(0);
        double rmse = Math.sqrt(mse);

        // Predict next price
        Dataset<Row> predDF = vaRF.transform(predRaw);
        double predicted = rfModel.transform(predDF)
            .select("prediction").first().getDouble(0);

        return new ModelResult(predicted, rmse);
    }

    // ── Main predict method — runs both models ────────────────────────────────
    private StockPrediction predict(SparkSession spark, String symbol) {
        List<Double> raw = repo.getPriceHistory(symbol, MAX_DATA);
        if (raw.size() < MIN_DATA) {
            log.warn("{}: only {} data points, need {}", symbol, raw.size(), MIN_DATA);
            return null;
        }

        // Reverse to chronological order
        Double[] prices = raw.toArray(new Double[0]);
        for (int i = 0, j = prices.length-1; i < j; i++, j--) {
            double t = prices[i]; prices[i] = prices[j]; prices[j] = t;
        }

        if (!pricesAreUsable(prices)) {
            log.warn("{}: price data failed validation, skipping", symbol);
            return null;
        }

        int n = prices.length;
        double current = prices[n-1];

        List<Row> rows = buildRows(prices);
        if (rows.size() < 5) {
            log.warn("{}: not enough valid training rows ({}), skipping", symbol, rows.size());
            return null;
        }

        StructType schema = buildSchema();
        Dataset<Row> df = spark.createDataFrame(rows, schema);

        // Assemble raw features (for LR pipeline)
        VectorAssembler va = new VectorAssembler()
            .setInputCols(new String[]{"lag1","lag2","lag3","lag4","lag5","ma5","momentum"})
            .setOutputCol("raw_features");
        Dataset<Row> assembled = va.transform(df);

        // Build prediction input row (last 5 prices)
        double l1=prices[n-1], l2=prices[n-2], l3=prices[n-3],
               l4=prices[n-4], l5=prices[n-5];
        double ma5=(l1+l2+l3+l4+l5)/5.0, mom=l1-l2;
        Dataset<Row> predRaw = spark.createDataFrame(
            Arrays.asList(RowFactory.create(l1,l2,l3,l4,l5,ma5,mom,0.0)), schema);

        // ── Run Linear Regression ──────────────────────────────────────────────
        ModelResult lr;
        try {
            lr = runLinearRegression(spark, assembled, predRaw, va, schema);
            if (!isValid(lr.predicted)) lr = new ModelResult(current, Double.MAX_VALUE);
        } catch (Exception e) {
            log.error("{} LR failed: {}", symbol, e.getMessage());
            lr = new ModelResult(current, Double.MAX_VALUE);
        }

        // ── Run Random Forest ──────────────────────────────────────────────────
        ModelResult rf;
        try {
            rf = runRandomForest(spark, assembled, predRaw, va);
            if (!isValid(rf.predicted)) rf = new ModelResult(current, Double.MAX_VALUE);
        } catch (Exception e) {
            log.error("{} RF failed: {}", symbol, e.getMessage());
            rf = new ModelResult(current, Double.MAX_VALUE);
        }

        log.info("{} | LR: pred={} rmse={} | RF: pred={} rmse={} | winner={}",
            symbol,
            String.format("%.4f", lr.predicted), String.format("%.4f", lr.rmse),
            String.format("%.4f", rf.predicted), String.format("%.4f", rf.rmse),
            lr.rmse <= rf.rmse ? "LinearRegression" : "RandomForest");

        return new StockPrediction(symbol, current,
            lr.predicted, lr.rmse,
            rf.predicted, rf.rmse,
            rows.size(), FMT.format(Instant.now()));
    }

    public void run() {
        log.info("=====================================================");
        log.info("  StockStream AI - Dual Model Prediction Engine");
        log.info("  Model 1 : Linear Regression (L-BFGS + StandardScaler)");
        log.info("  Model 2 : Random Forest (50 trees, depth=5)");
        log.info("  Winner  : Lower RMSE model used for signal");
        log.info("  Signals : BUY / HOLD / SELL");
        log.info("  Interval: {}s", INTERVAL / 1000);
        log.info("=====================================================");

        repo.createTableIfNotExists();
        SparkSession spark = buildSpark();
        spark.sparkContext().setLogLevel("WARN");

        int cycle = 0;
        while (!Thread.currentThread().isInterrupted()) {
            cycle++;
            log.info("-- Prediction Cycle {} --", cycle);
            List<String> symbols = repo.getAllSymbols();

            if (symbols.isEmpty()) {
                log.warn("No symbols yet - waiting for Spark consumer...");
            } else {
                int done = 0;
                for (String sym : symbols) {
                    try {
                        StockPrediction p = predict(spark, sym);
                        if (p != null) { repo.savePrediction(p); done++; }
                    } catch (Exception e) {
                        log.error("Prediction failed for {}: {}", sym, e.getMessage());
                    }
                }
                log.info("Cycle {} done - predicted {} / {} symbols", cycle, done, symbols.size());
            }

            try { Thread.sleep(INTERVAL); }
            catch (InterruptedException e) { Thread.currentThread().interrupt(); break; }
        }
        spark.stop();
    }

    public static void main(String[] args) {
        new PredictionEngine().run();
    }
}

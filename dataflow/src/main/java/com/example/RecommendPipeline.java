// dataflow/src/main/java/com/example/RecommendPipeline.java

package com.example;

import org.apache.beam.sdk.Pipeline;
import org.apache.beam.sdk.PipelineResult;
import org.apache.beam.sdk.io.gcp.bigquery.BigQueryIO;
import org.apache.beam.sdk.io.gcp.bigquery.BigQueryIO.Write.CreateDisposition;
import org.apache.beam.sdk.io.gcp.bigquery.BigQueryIO.Write.WriteDisposition;
import org.apache.beam.sdk.io.TextIO;
import org.apache.beam.sdk.options.Default;
import org.apache.beam.sdk.options.Description;
import org.apache.beam.sdk.options.PipelineOptions;
import org.apache.beam.sdk.options.PipelineOptionsFactory;
import org.apache.beam.sdk.options.Validation.Required;
import org.apache.beam.sdk.transforms.DoFn;
import org.apache.beam.sdk.transforms.ParDo;
import org.apache.beam.sdk.transforms.windowing.FixedWindows;
import org.apache.beam.sdk.transforms.windowing.Window;
import org.apache.beam.sdk.values.PCollection;
import org.joda.time.Duration;
import com.google.api.services.bigquery.model.TableFieldSchema;
import com.google.api.services.bigquery.model.TableRow;
import com.google.api.services.bigquery.model.TableSchema;
import java.util.ArrayList;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class RecommendPipeline {
    
    private static final Logger LOG = LoggerFactory.getLogger(RecommendPipeline.class);
    
    public interface RecommendPipelineOptions extends PipelineOptions {
        
        @Description("BigQueryプロジェクトID")
        @Required
        String getProject();
        void setProject(String value);
        
        @Description("入力CSVファイルパス")
        @Default.String("gs://test-recommend-engine-20250609-data-lake/input/*.csv")
        String getInputFile();
        void setInputFile(String value);
        
        @Description("BigQueryデータセット")
        @Default.String("recommend_data")
        String getDataset();
        void setDataset(String value);
        
        @Description("BigQueryテーブル")
        @Default.String("processed_transactions")
        String getTable();
        void setTable(String value);
    }
    
    // 取引データ変換処理
    static class ParseTransactionFn extends DoFn<String, TableRow> {
        
        @ProcessElement
        public void processElement(ProcessContext context) {
            String line = context.element();
            
            // CSVヘッダースキップ
            if (line.startsWith("transaction_id") || line.trim().isEmpty()) {
                return;
            }
            
            try {
                String[] fields = line.split(",");
                if (fields.length >= 6) {
                    TableRow row = new TableRow()
                        .set("transaction_id", fields[0].trim())
                        .set("user_id", Integer.parseInt(fields[1].trim()))
                        .set("product_id", Integer.parseInt(fields[2].trim()))
                        .set("quantity", Integer.parseInt(fields[3].trim()))
                        .set("price", Double.parseDouble(fields[4].trim()))
                        .set("timestamp", fields[5].trim())
                        .set("total_amount", 
                            Integer.parseInt(fields[3].trim()) * Double.parseDouble(fields[4].trim()))
                        .set("processed_time", java.time.Instant.now().toString());
                    
                    context.output(row);
                }
            } catch (Exception e) {
                LOG.warn("データパース失敗: " + line, e);
            }
        }
    }
    
    // ユーザー行動分析
    static class AnalyzeUserBehaviorFn extends DoFn<TableRow, TableRow> {
        
        @ProcessElement
        public void processElement(ProcessContext context) {
            TableRow transaction = context.element();
            
            try {
                // 簡単な行動分析ロジック
                Double totalAmount = (Double) transaction.get("total_amount");
                String category = "normal";
                
                if (totalAmount > 10000) {
                    category = "high_value";
                } else if (totalAmount > 5000) {
                    category = "medium_value";
                } else {
                    category = "low_value";
                }
                
                transaction.set("user_category", category);
                transaction.set("analysis_timestamp", java.time.Instant.now().toString());
                
                context.output(transaction);
            } catch (Exception e) {
                LOG.warn("ユーザー行動分析失敗", e);
                context.output(transaction);
            }
        }
    }
    
    public static void main(String[] args) {
        
        RecommendPipelineOptions options = PipelineOptionsFactory
            .fromArgs(args)
            .withValidation()
            .as(RecommendPipelineOptions.class);
        
        Pipeline pipeline = Pipeline.create(options);
        
        // BigQueryテーブルスキーマ定義
        TableSchema schema = new TableSchema().setFields(new ArrayList<TableFieldSchema>() {{
            add(new TableFieldSchema().setName("transaction_id").setType("STRING").setMode("REQUIRED"));
            add(new TableFieldSchema().setName("user_id").setType("INTEGER").setMode("REQUIRED"));
            add(new TableFieldSchema().setName("product_id").setType("INTEGER").setMode("REQUIRED"));
            add(new TableFieldSchema().setName("quantity").setType("INTEGER").setMode("NULLABLE"));
            add(new TableFieldSchema().setName("price").setType("FLOAT").setMode("NULLABLE"));
            add(new TableFieldSchema().setName("timestamp").setType("STRING").setMode("NULLABLE"));
            add(new TableFieldSchema().setName("total_amount").setType("FLOAT").setMode("NULLABLE"));
            add(new TableFieldSchema().setName("processed_time").setType("STRING").setMode("NULLABLE"));
            add(new TableFieldSchema().setName("user_category").setType("STRING").setMode("NULLABLE"));
            add(new TableFieldSchema().setName("analysis_timestamp").setType("STRING").setMode("NULLABLE"));
        }});
        
        // パイプライン処理
        PCollection<String> inputData = pipeline
            .apply("CSVファイル読み込み", TextIO.read().from(options.getInputFile()));
        
        PCollection<TableRow> parsedData = inputData
            .apply("取引データパース", ParDo.of(new ParseTransactionFn()));
        
        PCollection<TableRow> analyzedData = parsedData
            .apply("ユーザー行動分析", ParDo.of(new AnalyzeUserBehaviorFn()));
        
        // ウィンドウ処理（バッチ処理として）
        PCollection<TableRow> windowedData = analyzedData
            .apply("固定ウィンドウ", Window.into(FixedWindows.of(Duration.standardMinutes(5))));
        
        // BigQueryに書き込み
        windowedData
            .apply("BigQuery書き込み", BigQueryIO.writeTableRows()
                .to(String.format("%s:%s.%s", 
                    options.getProject(), 
                    options.getDataset(), 
                    options.getTable()))
                .withSchema(schema)
                .withCreateDisposition(CreateDisposition.CREATE_IF_NEEDED)
                .withWriteDisposition(WriteDisposition.WRITE_APPEND));
        
        PipelineResult result = pipeline.run();
        
        try {
            result.waitUntilFinish();
            LOG.info("パイプライン実行完了");
        } catch (Exception e) {
            LOG.error("パイプライン実行エラー", e);
        }
    }
}

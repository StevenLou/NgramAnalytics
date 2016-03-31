-- Set the split chunk size (min: 64MB, max: 512MB)
set hive.base.inputformat=org.apache.hadoop.hive.ql.io.HiveInputFormat;
set mapred.min.split.size=67108864;
set mapred.max.split.size=536870912;

-- Specifying the input data
set lang=eng-1M;
set ngram=1gram;
CREATE EXTERNAL TABLE IF NOT EXISTS ngrams (gram string, year int, occurrences bigint, pages bigint, books bigint) ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t' STORED AS SEQUENCEFILE LOCATION 's3://datasets.elasticmapreduce/ngrams/books/20090715/${hiveconf:lang}/${hiveconf:ngram}/';  
DESCRIBE ngrams;
SELECT * FROM ngrams LIMIT 10;

-- Normalizing input data
CREATE TABLE IF NOT EXISTS normalized (gram string, year int, occurrences bigint);
set min_year=1970;
set max_year=1995;
INSERT OVERWRITE TABLE normalized SELECT lower(gram), year, occurrences FROM ngrams WHERE year >= ('${hiveconf:min_year}' - 1) AND year <= '${hiveconf:max_year}' AND gram REGEXP "^[A-Za-z+'-]{3,}$";

-- Creating the ratios table
CREATE TABLE IF NOT EXISTS ratios (gram string, year int, ratio double);
INSERT OVERWRITE TABLE ratios SELECT a.gram, a.year, sum(a.occurrences) / b.total FROM normalized a JOIN (SELECT year, sum(occurrences) as total FROM normalized GROUP BY year)b ON a.year = b.year GROUP BY a.gram, a.year, b.total;

-- Calculating ratio chages year over year
set outputbucket=s3n://ngramjguo/output;
CREATE EXTERNAL TABLE IF NOT EXISTS output_table (gram string, year int, ratio double, increase double) ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t' STORED AS TEXTFILE LOCATION '${hiveconf:outputbucket}';
INSERT OVERWRITE TABLE output_table SELECT a.gram as gram, a.year as year, a.ratio as ratio, a.ratio / b.ratio as increase FROM ratios a JOIN ratios b ON a.gram = b.gram and a.year - 1 = b.year WHERE a.ratio > 0.000001 and a.year >= '${hiveconf:min_year}' and a.year <= '${hiveconf:max_year}' DISTRIBUTE BY year SORT BY year ASC, increase DESC;
SELECT year, gram, increase FROM output_table WHERE year = 1977 LIMIT 100;

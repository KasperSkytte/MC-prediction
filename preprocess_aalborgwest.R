#!/usr/bin/env Rscript
#load pkgs
require(ampvis2)
require(tidyverse)
require(data.table)

#############################
# Load, inspect, and filter data manually
#############################

#load config
config <- jsonlite::read_json("config.json", simplifyVector = TRUE)

#create output dir as defined in config
dir.create(paste0(config$results_dir, "/data_preprocessed"), recursive = TRUE)

#load metadata
metadata <- fread(paste0(config$data_dir, "/", config$metadata_filename))

#filter some samples
metadata <- metadata[!Plant %chin% c("EXTNEG", "PCRPOS", "PCRNEG", "", "CTRL") & Plant %chin% c("Aalborg W")]

#make sure date column is parsed correctly (year-month-day prefered) and
#sort chronologically, abundances will be sorted according to metadata by amp_load
metadata[[config$metadata_date_col]] <- lubridate::ymd(metadata[[config$metadata_date_col]])
metadata <- arrange(metadata, Date)
metadata <- metadata[, .(SampleID, Date, Plant)]

#load abundance table
otutable <- fread(paste0(config$data_dir, "/", config$abund_filename), fill = TRUE)

#load data into ampvis2, it handles so many things automagically
d <- amp_load(
  otutable = otutable,
  taxonomy = paste0(config$data_dir, "/", config$taxonomy_filename),
  metadata = metadata
)

#minimum 1k reads and normalise abundances (in % per sample)
d_s <- amp_subset_samples(d, minreads = 1000, removeAbsents = TRUE, normalise = TRUE)

##### also filter sparse samples with many zeros here instead of in python?

#write out filtered metadata
fwrite(d_s$metadata, file = paste0(config$results_dir, "/data_preprocessed/metadata.csv"))

#require at least 0.1% abundance in at least 1 sample
thedata <- ampvis2:::filter_species(d_s, filter_species = 0.1)

### don't touch the last line ###
#save ampvis2 object for manual inspection and to pass on to reformat.R
saveRDS(thedata, file = paste0(config$results_dir, "/data_preprocessed/ampvis2object.rds"))

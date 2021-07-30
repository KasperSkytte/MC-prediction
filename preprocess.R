#!/usr/bin/env Rscript
#load pkgs
require(ampvis2)
require(tidyverse)
require(data.table)

#############################
# Load and adjust data manually first
# This should be checked for every data set beforehand
# If this is done correctly, everything onwards shouldn't require any adjustment
#############################

#load config
config <- jsonlite::read_json("config.json", simplifyVector = TRUE)

#load metadata
metadata <- fread(paste0(config$data_dir, "/", config$metadata_filename))

#filter some samples
metadata <- metadata[!Plant %chin% c("EXTNEG", "PCRPOS", "PCRNEG", "", "CTRL") & Plant %chin% c("Aalborg W")]

#make sure date column is parsed correctly (year-month-day prefered) and
#sort chronologically, abundances will be sorted according to metadata by amp_load
metadata[[config$metadata_date_col]] <- lubridate::ymd(metadata[[config$metadata_date_col]])
metadata <- arrange(metadata, Date)
metadata <- metadata[, .(SampleID, Date, Plant)]

#############################
# The rest from here shouldn't require any adjustment
#############################

#load data into ampvis2, it handles so many things automatically
d_raw <- amp_load(
  otutable = paste0(config$data_dir, "/", config$abund_filename),
  taxonomy = paste0(config$data_dir, "/", config$taxonomy_filename),
  metadata = metadata
)

#minimum 1k reads and normalise abundances (in % per sample)
d_raw_s <- amp_subset_samples(d_raw, minreads = 1000, removeAbsents = TRUE, normalise = TRUE)

##### also filter sparse samples with many zeros here instead of in python? #####

#write out filtered metadata
fwrite(d_raw_s$metadata, file = paste0(config$data_dir, "/preprocessed/metadata.csv"))

#require at least 0.1% abundance in at least 1 sample
d_raw_sn <- ampvis2:::filter_species(d_raw_s, filter_species = 0.1)

#aggregate data at chosen taxonomic level, must not be higher than Genus level
#as functional info is at genus level, so one of: OTU, Species, Genus
if(length(config$tax_level) != 1L)
  stop("Please only supply one taxonomic level")

valid_taxlevels <- c("OTU", "Species", "Genus", "Family", "Order", "Class", "Phylum", "Kingdom")
if (!tolower(config$tax_level) %chin% tolower(valid_taxlevels[1:3]))
  stop("Invalid taxonomic level, valid levels are: \n", paste0(valid_taxlevels[1:3], collapse = ", "))

#construct a vector from chosen tax level and up, removing lower levels
tax_ID <- which(valid_taxlevels %chin% config$tax_level)
tax_aggregate <- valid_taxlevels[tax_ID:length(valid_taxlevels)]

#round to 3 decimals
d_raw_sn$abund[] <- lapply(d_raw_sn$abund, round, 3)

#aggregate data
otutable <- ampvis2:::aggregate_abund(
  abund = d_raw_sn$abund,
  tax = d_raw_sn$tax,
  tax_aggregate = tax_aggregate,
  format = "abund", 
  calcSums = FALSE
)

#extract new taxonomy from the aggregated data
taxonomy <- data.frame(tax = rownames(otutable), check.names = FALSE, stringsAsFactors = FALSE)
taxonomy <- separate(taxonomy, col = "tax", into = tax_aggregate, sep = "; ")
# fwrite(
#   transpose(taxonomy, keep.names = "names"), 
#   paste0(config$data_dir, "/preprocessed/taxonomy.csv"),
#   col.names = FALSE,
#   quote = FALSE
# )

#use only the chosen tax level as ID's, keep the remaining taxonomy in taxonomy
rownames(otutable) <- taxonomy[[tax_aggregate[1]]]
#transpose abundances and write out
abund_t <- rownames_to_column(as.data.frame(t(otutable)), colnames(d_raw_sn$metadata)[1])
fwrite(abund_t, file = paste0(config$data_dir, "/preprocessed/abundances.csv"))

#Download or read MiDAS field guide functional data
#midasgenusfunctions <- ampvis2:::extractFunctions(ampvis2:::getMiDASFGData())
#setDT(midasgenusfunctions)
midasgenusfunctions <- data.table::fread("data/genusfunctions_20201201.csv")

#reformat
knownfuncs <- midasgenusfunctions[
    ,
    Genus := paste0("g__", stringr::str_replace_all(
      Genus,
      c("candidatus" = "Candidatus",
      " " = "_",
      "[^[:alnum:]_\\.\\-]" = ""
    )))
  ]

#filter Genera to match only those in the data
knownfuncs <- filter(knownfuncs, Genus %chin% unique(taxonomy$Genus))

#extract chosen functions
knownfuncs <- knownfuncs %>% select(Genus, starts_with(config$functions))

#Aggregate ":In situ" and ":Other" columns for each function
#In situ always wins if not "na", otherwise that in "Other" is used
#melt, do groupwise operation per genus and function, then cast back
knownfuncs <- melt(knownfuncs, id.vars = "Genus")
knownfuncs[, func := gsub(":.*$", "", variable)]
knownfuncs <- knownfuncs[
  ,
  .(
    newvalue = if(all(value %chin% "na")) 
      "na"
    else if(.SD[grepl(":In situ$", variable), value] != "na")
      .SD[grepl(":In situ$", variable), value]
    else if(.SD[grepl(":In situ$", variable), value] == "na")
      .SD[grepl(":Other$", variable), value]
  ),
  by = .(Genus, func)
]
knownfunctions <- dcast(knownfuncs, Genus~func, value.var = "newvalue")

###merge with otutable (incl taxonomy)
#first make a DF with ALL Genera in both otutable and function data
func_genus <- full_join(unique(taxonomy[,"Genus", drop = FALSE]), knownfunctions, by = "Genus")

#remove all unclassified taxa at Genus level but one
func_genus <- filter(func_genus, !Genus %chin% "")
func_genus <- rbind(func_genus, c("", rep("na", ncol(func_genus)-1L)))
func_genus[is.na(func_genus)] <- "na"

#merge 
func_tax <- left_join(taxonomy, func_genus, by = "Genus")

fwrite(func_tax, file = paste0(config$data_dir, "/preprocessed/taxonomy_wfunctions.csv"))

#return abund, func_tax, clusters, config['functions']
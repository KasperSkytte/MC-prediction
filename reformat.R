#!/usr/bin/env Rscript
#load pkgs
suppressPackageStartupMessages({
  require(ampvis2)
  require(tidyverse)
  require(data.table)
})

#load config
config <- jsonlite::read_json("config.json", simplifyVector = TRUE)

#create output dir for reformatted data
dir.create(
  paste0(config$results_dir, "/data_reformatted"),
  recursive = TRUE,
  showWarnings = FALSE
)

#verify and combine data using amp_load
thedata <- amp_load(
  otutable = config$abund_file,
  metadata = config$metadata_file,
  taxonomy = config$taxonomy_file
)

#aggregate data at chosen taxonomic level, must not be higher than Genus level
#as functional info is at genus level, so one of: OTU, Species, Genus
if(length(config$tax_level) != 1L)
  stop("Please only supply a single taxonomic level")

valid_taxlevels <- c("OTU", "Species", "Genus", "Family", "Order", "Class", "Phylum", "Kingdom")
if (!tolower(config$tax_level) %chin% tolower(valid_taxlevels[1:3]))
  stop("Invalid taxonomic level, valid levels are: \n", paste0(valid_taxlevels[1:3], collapse = ", "))

#construct a vector from chosen tax level and up, removing lower levels
tax_ID <- which(valid_taxlevels %chin% config$tax_level)
tax_aggregate <- valid_taxlevels[tax_ID:length(valid_taxlevels)]

#round to 3 decimals
thedata$abund[] <- lapply(thedata$abund, round, 3)

#aggregate data
otutable <- ampvis2:::aggregate_abund(
  abund = thedata$abund,
  tax = thedata$tax,
  tax_aggregate = tax_aggregate,
  format = "abund", 
  calcSums = FALSE
)

#extract new taxonomy from the aggregated data
taxonomy <- data.frame(tax = rownames(otutable), check.names = FALSE, stringsAsFactors = FALSE)
taxonomy <- separate(taxonomy, col = "tax", into = tax_aggregate, sep = "; ")
# fwrite(
#   transpose(taxonomy, keep.names = "names"), 
#   paste0(config$results_dir, "/data_reformatted/taxonomy.csv"),
#   col.names = FALSE,
#   quote = FALSE
# )

#use only the chosen tax level as ID's, keep the remaining taxonomy in taxonomy
rownames(otutable) <- taxonomy[[tax_aggregate[1]]]
#transpose abundances and write out
abund_t <- rownames_to_column(as.data.frame(t(otutable)), colnames(thedata$metadata)[1])
fwrite(abund_t, file = paste0(config$results_dir, "/data_reformatted/abundances.csv"))

#Download or read MiDAS field guide functional data
#midasgenusfunctions <- ampvis2:::extractFunctions(ampvis2:::getMiDASFGData())
#setDT(midasgenusfunctions)
midasgenusfunctions <- data.table::fread("data/MiDAS_genusfunctions_20211109.csv") #this is hardcoded, remove before committing. Pull from field guide instead

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
# 
# #Aggregate ":In situ" and ":Other" columns for each function
# #In situ always wins if not "na", otherwise that in "Other" is used
# #melt, do groupwise operation per genus and function, then cast back
# knownfuncs <- melt(knownfuncs, id.vars = "Genus")
# knownfuncs[, func := gsub(":.*$", "", variable)]
# knownfuncs <- knownfuncs[
#   ,
#   .(
#     newvalue = if(all(value %chin% "na")) 
#       "na"
#     else if(.SD[grepl(":In situ$", variable), value] != "na")
#       .SD[grepl(":In situ$", variable), value]
#     else if(.SD[grepl(":In situ$", variable), value] == "na")
#       .SD[grepl(":Other$", variable), value]
#   ),
#   by = .(Genus, func)
# ]
# knownfunctions <- dcast(knownfuncs, Genus~func, value.var = "newvalue")

knownfunctions <- knownfuncs

###merge with otutable (incl taxonomy)
#first make a DF with ALL Genera in both otutable and function data
func_genus <- full_join(unique(taxonomy[,"Genus", drop = FALSE]), knownfunctions, by = "Genus")

#remove all unclassified taxa at Genus level but one
func_genus <- filter(func_genus, !Genus %chin% "")
func_genus <- rbind(func_genus, c("", rep("na", ncol(func_genus)-1L)))
func_genus[is.na(func_genus)] <- "na"

#merge 
func_tax <- left_join(taxonomy, func_genus, by = "Genus")

fwrite(func_tax, file = paste0(config$results_dir, "/data_reformatted/taxonomy_wfunctions.csv"))

#dont forget the metadata
fwrite(thedata$metadata, paste0(config$results_dir, "/data_reformatted/metadata.csv"))

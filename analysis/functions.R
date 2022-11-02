#' @title Function to plot prediction accuracy for each clustering type
#'
#' @param results_dir Output results folder as produced from a single run of run.bash
#' @param tablename Name of object assigned to the global environment
#'
#' @return
#' @export
#'
#' @examples
plot_performance <- function(results_dir, tablename = "performance_table") {
  filenames <- c(
    "lstm_idec_performance.txt",
    "lstm_abund_performance.txt",
    "lstm_func_performance.txt"
  )
  list <- lapply(
    file.path(results_dir, filenames),
    function(filepath) {
      dt <- fread(filepath)
      colnames(dt) <- gsub("[\\['\\]]*", "", colnames(dt))
      dt[, cluster := gsub(":.*$", "", `bray-curtis`)]
      dt <- dt[
        ,
        lapply(
          .SD,
          gsub,
          pattern = "^[0-9]+:.*\\[|\\]$",
          replacement = ""
        )
      ]
      dt <- dt[
        ,
        lapply(.SD, as.numeric)
      ]
      dt <- melt(
        dt,
        id.vars = "cluster",
        variable.name = "errorfunc",
        value.name = "value"
      )
      dt[
        ,
        clustertype := tools::file_path_sans_ext(basename(filepath))
      ]
      dt[
        ,
        name := basename(results_dir)
      ]
      dt
    }
  )
  dt <- rbindlist(list)
  if (!exists(tablename, .GlobalEnv)) {
    assign(tablename, dt, .GlobalEnv)
  } else {
    assign(
      tablename,
      rbindlist(list(get(tablename, .GlobalEnv), dt)),
      .GlobalEnv
    )
  }
  plot <- ggplot(
    dt,
    aes(
      x = cluster,
      y = value,
      group = clustertype,
      color = clustertype,
      fill = clustertype
    )
  ) +
    geom_col(position = "dodge2") +
    facet_wrap("errorfunc", scales = "free_y", ncol = 1) +
    ylim(0, 1)
  print(plot)
  cli::cat_line(readLines(paste0(path, "/idec_performance.txt")))
}

#' @title Read reformatted amplicon data from a results folder
#' @description Read the amplicon data in the data_reformatted subfolder of a results run into an ampvis2 object
#'
#' @param results_dir Output results folder as produced from a single run of run.bash
#'
#' @return An ampvis2 class object
#' @export
#'
#' @examples
load_data_reformatted <- function(results_dir) {
  abund <- fread(
    file.path(results_dir, "data_reformatted/abundances.csv"),
    data.table = FALSE
  ) %>%
    t() %>%
    as.data.frame() %>% {
      colnames(.) <- .[1, ]
      . <- .[-1, ]
      .[] <- lapply(., as.numeric)
      .[["ASV"]] <- rownames(.)
      .
    }

  amp_load(
    otutable = abund,
    metadata = file.path(
      results_dir,
      "data_reformatted/metadata.csv"
    ),
    taxonomy = file.path(
      results_dir,
      "data_reformatted/taxonomy_wfunctions.csv"
    )
  )
}

#' @title Read and parse model performance
#' @description Read and parse a performance summary lstm_{idec,abund,func}_performance.txt file and return as data table
#'
#' @param file File path to a *_performance.txt file
#'
#' @return A data.table
#' @export
#'
#' @examples
parse_performance <- function(file) {
  if (!file.exists(file)) {
    warning("file ", file, " doesn't exist, skipping...")
    return(NULL)
  }

  dt <- fread(file)
  colnames(dt) <- stringi::stri_replace_all_regex(
    colnames(dt),
    pattern = "[\\[\\'\\]]",
    replacement = ""
  )
  dt$cluster_no <- stringi::stri_replace_all_regex(dt[[1]], ":.*$", "")


  dt[] <- lapply(
    dt,
    stringi::stri_replace_all_regex,
    pattern = "^[^\\[]*\\[|\\]$",
    replacement = ""
  )
  dt[] <- lapply(dt, as.numeric)

  dt <- melt(
    dt,
    id.vars = NULL,
    measure.vars = 1:3,
    variable.name = "error_metric",
    value = "value"
  )

  return(dt)
}

#' @title Read and parse all model performance files
#' @description Read ALL performance summary files from a single run, reformat, prettify and combine into a single data table
#'
#' @param results_dir Path to a results folder as produced by run.bash
#'
#' @return A data.table
#' @export
#'
#' @examples
read_results <- function(results_dir) {
  filenames <- c(
    "lstm_idec_performance.txt",
    "lstm_abund_performance.txt",
    "lstm_func_performance.txt"
  )

  results_list <- lapply(
    file.path(results_dir, filenames),
    parse_performance
  )
  names(results_list) <- gsub("_performance.txt$", "", filenames)

  dt <- rbindlist(results_list, idcol = "cluster_type")

  logfile <- fread(
    list.files(
      results_dir,
      pattern = "log_[0-9]*_[0-9]*\\.txt",
      full.names = T
    ),
    sep = "\n",
    header = FALSE,
    col.names = "line"
  )

  dt$dataset <- basename(
    gsub(
      "\\/ASVtable.*$",
      "",
      logfile[grepl(".*ASVtable.*", line), line]
    )
  )

  #read metadata to get the number of samples to append dataset names
  metadata <- fread(
    file.path(results_dir, "data_reformatted", "metadata.csv")
  )

  dt$dataset <- paste0(
    dt$dataset,
    " (",
    gsub(
      "[^0-9]*",
      "",
      logfile[grepl("predict_timestamp", line), line]),
      " P.S.)"
    )

  dt$cluster_type <- stringr::str_replace_all(
    dt$cluster_type,
    pattern = c(
      "lstm_abund" = "Single ASV",
      "lstm_func" = "Biological function",
      "lstm_idec" = "IDEC"
    )
  )

  dt$error_metric <- stringr::str_replace_all(
    dt$error_metric,
    pattern = c(
      "bray-curtis" = "Bray Curtis",
      "mean_squared_error" = "Mean Squared Error",
      "mean_absolute_error" = "Mean Absolute Error"
    )
  )
  return(dt)
}

#' @title Boxplot of model accuracy per batch (produced by loop_datasets.bash)
#' @description Read all performance summary files from a batch of multiple runs (i.e. WWTPs) and plot a summary boxplot. Will also save the plot to a PNG file in each folder.
#'
#' @param results_batch_dir Path to a folder containing one or more subfolders, each produced by run.bash (i.e. produced by loop_datasets.bash)
#'
#' @return A ggplot2 object
#' @export
#'
#' @examples
plot_all <- function(results_batch_dir) {
  runs <- list.dirs(
    results_batch_dir,
    full.names = TRUE,
    recursive = FALSE
  )
  if (length(runs) == 0) {
    stop("No results folders found, wrong working directory?")
  }

  d_list <- lapply(runs, read_results)
  names(d_list) <- runs
  combined <- rbindlist(
    d_list,
    idcol = "results_folder",
    fill = TRUE
  )[
    !is.na(cluster_type) & value > 0
  ]

  #order datasets by the number of samples (extracted from dataset names)
  combined[,unique(dataset)] %>%
    stringi::stri_extract_all_regex("\\(.*$", "") %>%
    stringi::stri_extract_all_regex("[0-9]+") %>%
    as.numeric -> nsamples
  datasets_ordered <- combined[
    ,
    unique(dataset)
  ][
    order(nsamples, decreasing = F)
  ]
  combined[, dataset := factor(dataset, levels = datasets_ordered)]

  # create a list of plots for each error metric
  plot_list <- combined %>%
    split(.[["error_metric"]]) %>%
    lapply(
      function(dt) {
        ggplot(
          dt,
          aes(
            cluster_type,
            value,
            color = cluster_type
          )
        ) +
          geom_boxplot(
            outlier.shape = 1,
            outlier.size = 1
          ) +
          facet_grid(
            rows = vars(error_metric),
            cols = vars(dataset),
            scales = "free"
          ) +
          theme(
            legend.position = "none",
            legend.title = element_blank(),
            axis.text.x = element_blank(),
            axis.title = element_blank(),
            axis.ticks.x = element_blank(),
            strip.text.x = element_blank(),
            panel.grid.major.x = element_blank(),
            panel.grid.minor.y = element_blank()
          ) +
          scale_color_brewer(palette = "Set2")
      }
    )

  # The first plot will be at the top and show facet strips but no x axis text
  # Bray-Curtis axis breaks must be set between 0 - 1
  plot_list[[1]] <- plot_list[[1]] +
    theme(
      axis.ticks.x = element_blank(),
      strip.text.x = element_text(angle = 90)
    ) +
    scale_y_continuous(
      trans = "sqrt",
      breaks = c(0, 0.05, 0.1, seq(0.2, 1, 0.2))
    )

  # Increase the number of axis breaks for the middle plot
  plot_list[[2]] <- plot_list[[2]] +
  scale_y_continuous(
    trans = "sqrt",
    breaks = scales::extended_breaks(7)
  )

  # The last plot will be at the bottom and
  # show no facet strips but will show x axis text
  # increase the number of axis breaks
  plot_list[[length(plot_list)]] <- plot_list[[length(plot_list)]] +
    theme(
      strip.text.x = element_blank(),
      legend.position = "bottom",
      legend.title = element_text()
    ) +
    scale_y_continuous(
      trans = "sqrt",
      breaks = scales::extended_breaks(7)
    ) +
    labs(color = "Clustering type")

  # Compose all plots in the list using patchwork
  plot <- purrr::reduce(
    plot_list,
    `/`
  )

  ggsave(
    file.path(dirname(combined[1, results_folder]), "boxplot_all.png"),
    plot = plot,
    width = 12,
    height = 8
  )

  return(plot)
}

#' @title Read predicted abundance files from a single run
#' @description Read all predicted abundance tables (across all cluster types) for a single run and combine
#'
#' @param results_dir Path to a results folder as produced by run.bash
#' @param pattern A regex pattern for file names to search for
#' @param sample_prefix Prefix for sample names (i.e. true_ or predicted_)
#'
#' @return A data.table
#' @export
#'
#' @examples
read_abund <- function(results_dir, pattern, sample_prefix = "") {
  abund_files <- list.files(
    file.path(results_dir, "data_predicted"),
    pattern = pattern,
    recursive = FALSE,
    include.dirs = FALSE,
    full.names = TRUE
  )
  abund_list <- lapply(
    abund_files,
    function(file) {
      #first read each file
      file <- fread(
        file,
        sep = ",",
        header = TRUE
      )

      #melt to be able to rowbind all files
      abund <- melt(
        file,
        id.vars = "Sample",
        variable.name = "OTU",
        value.name = "abundance"
      )
      abund[[1]] <- paste0(sample_prefix, abund[[1]])
      return(abund)
    }
  )

  abund_dt <- rbindlist(abund_list)

  #negative abundances doesn't make sense
  sub_zeros <- abund_dt$abundance < 0L
  if (sum(sub_zeros) > 0) {
    warning(
      sum(sub_zeros),
      " negative abundance values have been set to 0"
    )
    abund_dt$abundance[sub_zeros] <- 0L
  }
  abund <- dcast(
    abund_dt,
    OTU~Sample,
    value.var = "abundance"
  )

  return(abund)
}

#' @title Read and combine both true and predicted abundance data
#' @description read and combine both original and predicted abundance data (incl metadata+tax) from all cluster types into a single ampvis2 object
#'
#' @param results_dir Path to a results folder as produced by run.bash
#' @param cluster_type From which cluster type should the predicted data be from (i.e. abund, func, or idec)
#'
#' @return An ampvis2 class object
#' @export
#'
#' @examples
combine_abund <- function(results_dir, cluster_type) {
  cluster_types <- c("abund", "func", "idec")
  if (length(cluster_type) != 1L || !any(cluster_type %in% cluster_types)) {
    stop(
      "cluster_type must be one of: ",
      paste0(cluster_types, collapse = ", "))
  }

  #read predicted abundance tables
  pred_abund <- read_abund(
    results_dir = results_dir,
    pattern = paste0("lstm_", cluster_type, ".*predicted\\.csv"),
    sample_prefix = "pred_"
  )

  #read true abundance tables
  true_abund <- read_abund(
    results_dir = results_dir,
    pattern = paste0("lstm_", cluster_type, ".*dataall_nontrans\\.csv"),
    sample_prefix = "true_"
  )

  #read dates and sample IDs and use as metadata
  #dates per sample are the same for all
  #just use the first file as metadata for all
  metadata <- fread(
    list.files(
      file.path(results_dir, "data_splits"),
      pattern = ".*dates(_all)*\\.csv",
      recursive = FALSE,
      include.dirs = FALSE,
      full.names = TRUE
    )[[1]]
  )

  #add a split_dataset column with whether
  #the particular dates are used for train, val, or test
  metadata_split_datasets <- rbindlist(
    lapply(
      file.path(
        results_dir,
        "data_splits",
        c("dates_train.csv", "dates_val.csv", "dates_test.csv")
      ),
      function(file) {
        if (file.exists(file)) {
          dt <- fread(
            file
          )
          dt[, split_dataset := gsub(".*_|\\.csv", "", file)] #train, val, or test #nolint
          dt
        }
      }
    )
  )

  #checks for when data is produced by older versions of the pipeline
  if (sum(dim(metadata_split_datasets)) != 0L) {
    #if using no validation data, it will be identical to test data
    #remove it
    if (
      any(
        metadata_split_datasets[split_dataset == "val"][["Sample"]] %chin%
        metadata_split_datasets[split_dataset == "test"][["Sample"]]
      )
    ) {
      metadata_split_datasets <- metadata_split_datasets[split_dataset != "val"]
    }
    metadata <- metadata_split_datasets[metadata, on = c("Sample", "Date")]
  } else if (sum(dim(metadata_split_datasets)) == 0L) {
    metadata[, split_dataset := "predicted"]
  }

  #load predicted and true data
  predicted_data <- amp_load(
    otutable = pred_abund,
    metadata = metadata[
      ,
      .(
        Sample = paste0("pred_", Sample),
        Date,
        predicted = "predicted",
        split_dataset
      )
    ],
    taxonomy = file.path(
      results_dir,
      "data_reformatted",
      "taxonomy_wfunctions.csv"
    )
  )

  true_data <- amp_load(
    otutable = true_abund,
    metadata = metadata[
      ,
      .(
        Sample = paste0("true_", Sample),
        Date,
        predicted = "real",
        #all dates here are from the original data
        #set before split, not train, val, or test:
        split_dataset = "real"
      )
    ],
    taxonomy = file.path(
      results_dir,
      "data_reformatted",
      "taxonomy_wfunctions.csv"
    )
  )

  combined <- amp_merge_ampvis2(
    predicted_data,
    true_data,
    by_refseq = FALSE
  )

  return(combined)
}

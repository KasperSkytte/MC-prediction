plot_performance <- function(path, tablename = "performance_table") {
  filenames <- c("lstm_idec_performance.txt", "lstm_abund_performance.txt", "lstm_func_performance.txt")
  list <- lapply(paste0(path, "/", filenames), function(filepath) {
    dt <- fread(filepath)
    colnames(dt) <- gsub("[\\['\\]]*", "", colnames(dt))
    dt[, cluster := gsub(":.*$", "", `bray-curtis`)]
    dt <- dt[,lapply(.SD, gsub, pattern = "^[0-9]+:.*\\[|\\]$", replacement = "")]
    dt <- dt[,lapply(.SD, as.numeric)]
    dt <- melt(dt, id.vars = "cluster", variable.name = "errorfunc", value.name = "value")
    dt[, clustertype := tools::file_path_sans_ext(basename(filepath))]
    dt[, name := basename(path)]
    dt
  })
  dt <- rbindlist(list)
  if (!exists(tablename, .GlobalEnv)) {
    assign(tablename, dt, .GlobalEnv)
  } else {
    assign(tablename, rbindlist(list(get(tablename, .GlobalEnv), dt)), .GlobalEnv)
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

load_16sdata <- function(results_dir) {
  abund <- fread(
    file.path(results_dir, "data_reformatted/abundances.csv")
  )

  abund_melted <- melt(
    abund,
    id.vars = c("Sample"),
    variable.name = "ASV",
    value.name = "abundance",
    variable.factor = FALSE)
  abund_cast <- dcast(
    abund_melted,
    ASV~Sample,
    value.var = "abundance"
  )

  amp_load(
    otutable = abund_cast,
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
      "mean_squared_error" = "Mean Squared Error (MSE)",
      "mean_absolute_error" = "Mean Absolute Error (MAE)"
    )
  )
  return(dt)
}

plot_all <- function(results_batch_dir) {
  runs <- list.files(
    results_batch_dir,
    pattern = "^results_.*",
    full.names = TRUE
  )
  if (length(runs) == 0) {
    stop("No results folders found, wrong working directory?")
  }

  d_list <- lapply(runs, read_results)
  names(d_list) <- runs
  d <- rbindlist(
    d_list,
    idcol = "results_folder",
    fill = TRUE
  )[
    !is.na(cluster_type)
  ]

  plot <- ggplot(
    d[value > 0],
    aes(
      cluster_type,
      value,
      color = cluster_type
    )
  ) +
    geom_boxplot() +
    facet_grid(
      rows = vars(error_metric),
      cols = vars(dataset), scales = "free_y"
    ) +
    theme(
      axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5),
      legend.title = element_blank(),
      axis.title = element_blank()
    ) +
    scale_color_discrete(
      labels = c(
        lstm_idec = "IDEC",
        lstm_func = "Metab. function",
        lstm_abund = "Single ASV"
      )
    )

  ggsave(
    file.path(dirname(d[1, results_folder]), "boxplot_all.png"),
    plot = plot,
    width = 14,
    height = 8
  )

  return(plot)
}

#abundance tables
read_abund <- function(dir, pattern, sample_prefix = "") {
  abund_files <- list.files(
    dir,
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

#abund, func, idec
combine_abund <- function(results_dir, cluster_type) {
  cluster_types <- c("abund", "func", "idec")
  if (length(cluster_type) != 1L || !any(cluster_type %in% cluster_types)) {
    stop("cluster_type must be one of: ", paste0(cluster_types, collapse = ", "))
  }

  #read predicted abundance tables
  pred_abund <- read_abund(
    dir = file.path(results_dir, "data_predicted"),
    pattern = paste0("lstm_", cluster_type, ".*predicted\\.csv"),
    sample_prefix = "pred_"
  )

  #read true abundance tables
  true_abund <- read_abund(
    dir = file.path(results_dir, "data_predicted"),
    pattern = paste0("lstm_", cluster_type, ".*dataall\\.csv"),
    sample_prefix = "true_"
  )

  #read dates and sample IDs and use as metadata
  metadata_files <- list.files(
    file.path(results_dir, "data_predicted"),
    pattern = paste0("lstm_", cluster_type, ".*dates\\.csv"),
    recursive = FALSE,
    include.dirs = FALSE,
    full.names = TRUE
  )
  #dates per sample are the same for all
  #just use the first file as metadata for all
  metadata <- fread(metadata_files[[1]])

  #load predicted data
  predicted_data <- amp_load(
    otutable = pred_abund,
    metadata = metadata[, .(Sample = paste0("pred_", Sample), Date, predicted = "predicted")]
  )
  true_data <- amp_load(
    otutable = true_abund,
    metadata = metadata[, .(Sample = paste0("true_", Sample), Date, predicted = "real")]
  )

  combined <- amp_merge_ampvis2(
    predicted_data,
    true_data,
    by_refseq = FALSE
  )

  return(combined)
}
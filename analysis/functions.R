# Helper functions sourced by the R markdown files in this folder.
# Requires ampvis2, data.table, ggplot2, patchwork, lubridate and tune to be
# attached, and igraph, tidygraph and ggraph to be installed for plot_graph().

# Colors and legend labels for real data and each part of the predicted data,
# in the order they should appear in legends
split_dataset_colors <- c(
  real = "black",
  train = "#bd2929",
  val = "#e0b01c",
  test = "#16a085",
  future = "blue"
)
split_dataset_labels <- c(
  real = "Real",
  train = "Prediction-Train",
  val = "Prediction-Validation",
  test = "Prediction-Test",
  future = "Prediction-Future"
)

#' @title Read reformatted amplicon data from a results folder
#' @description Read the amplicon data in the data_reformatted subfolder of a results run into an ampvis2 object
#'
#' @param results_dir Output results folder as produced from a single run of run.bash
#'
#' @return An ampvis2 class object
load_data_reformatted <- function(results_dir) {
  abund <- fread(
    file.path(results_dir, "data_reformatted/abundances.csv"),
    data.table = FALSE
  )
  # samples are rows, taxa are columns
  otutable <- as.data.frame(t(abund[, -1]))
  colnames(otutable) <- abund[[1]]
  otutable$ASV <- rownames(otutable)

  amp_load(
    otutable = otutable,
    metadata = file.path(results_dir, "data_reformatted/metadata.csv"),
    taxonomy = file.path(results_dir, "data_reformatted/taxonomy_wfunctions.csv")
  )
}

#' @title Read and parse model performance
#' @description Read and parse a performance summary {lstm,graph}_{idec,abund,func,graph}_performance.txt file and return as data table
#'
#' @param file File path to a *_performance.txt file
#'
#' @return A data.table with columns cluster_no, error_metric, value, predwindow
parse_performance <- function(file) {
  dt <- fread(file)
  # header is a python list
  colnames(dt) <- stringi::stri_replace_all_regex(
    colnames(dt),
    pattern = "[\\[\\'\\]]",
    replacement = ""
  )
  # cluster IDs before brackets
  dt$cluster_no <- stringi::stri_replace_all_regex(dt[[1]], ":.*$", "")

  # remove brackets and cluster IDs
  dt[] <- lapply(
    dt,
    stringi::stri_replace_all_regex,
    pattern = "^[^\\[]*\\[|\\]$",
    replacement = ""
  )
  dt[] <- lapply(dt, as.numeric)
  if ("loss" %in% colnames(dt)) {
    dt[, loss := NULL]
  }

  dt <- melt(
    dt,
    id.vars = "cluster_no",
    variable.name = "error_metric",
    value.name = "value"
  )

  # extract predwindow from error_metric, e.g. bray_curtis_10
  dt[, predwindow := as.integer(gsub("^.*_", "", error_metric))]
  dt[, error_metric := gsub("_[0-9]+$", "", error_metric)]

  return(dt)
}

#' @title Read and parse all model performance files
#' @description Read ALL performance summary files from a single run, reformat, prettify and combine into a single data table
#'
#' @param results_dir Path to a results folder as produced by run.bash
#' @param add_numsamples If TRUE append the number of samples in the dataset to the dataset name, e.g. "Aalborg W (300)"
#'
#' @return A data.table
read_performance <- function(results_dir, add_numsamples = TRUE) {
  files <- list.files(
    results_dir,
    pattern = "_performance\\.txt$",
    full.names = TRUE
  )
  results_list <- lapply(files, parse_performance)
  names(results_list) <- sub("_performance\\.txt$", "", basename(files))

  dt <- rbindlist(results_list, idcol = "cluster_type")

  dt$dataset <- basename(results_dir)

  if (isTRUE(add_numsamples)) {
    metadata <- fread(
      file.path(results_dir, "data_reformatted", "metadata.csv")
    )
    dt$dataset <- paste0(dt$dataset, " (", nrow(metadata), ")")
  }

  cluster_type_names <- c(
    lstm_abund = "Ranked abundance",
    lstm_func = "Biological function",
    lstm_idec = "IDEC",
    graph_abund = "Ranked abundance",
    graph_func = "Biological function",
    graph_idec = "IDEC",
    graph_graph = "Graph"
  )
  error_metric_names <- c(
    bray_curtis = "Bray Curtis",
    mse = "Mean Squared Error",
    mae = "Mean Absolute Error"
  )
  dt[, cluster_type := unname(cluster_type_names[cluster_type])]
  dt[, error_metric := unname(error_metric_names[error_metric])]

  return(dt)
}

#' @title Boxplot of model accuracy per batch (produced by loop_datasets.bash)
#' @description Read all performance summary files from a batch of multiple runs (i.e. WWTPs) and plot a summary boxplot with one row per prediction window. Optionally saves the plot in results_batch_dir.
#'
#' @param results_batch_dir Path to a folder containing one or more subfolders, each produced by run.bash (i.e. produced by loop_datasets.bash)
#'
#' @return A patchwork object (invisibly)
boxplot_all <- function(
  results_batch_dir,
  add_numsamples = TRUE,
  filename = "boxplot_all.png",
  save = TRUE,
  error_metrics = c("Bray Curtis", "Mean Squared Error", "Mean Absolute Error"),
  cluster_types = c("Graph", "IDEC", "Ranked abundance", "Biological function"),
  plot_width = 180,
  plot_height = 185,
  cluster_type_colors = c(
    "Biological function" = "#422537",
    "Graph" = "#D58078",
    "IDEC" = "#86A556",
    "Ranked abundance" = "#624FB0"
  )
) {
  runs <- list.dirs(
    results_batch_dir,
    full.names = TRUE,
    recursive = FALSE
  )
  if (length(runs) == 0) {
    stop("No results folders found in \"", results_batch_dir, "\", wrong working directory?")
  }

  combined <- rbindlist(
    lapply(runs, read_performance, add_numsamples = add_numsamples),
    fill = TRUE
  )
  combined <- combined[
    value > 0 &
      error_metric %chin% error_metrics &
      cluster_type %chin% cluster_types
  ]

  # order datasets by the number of samples (in parentheses), then by name
  datasets <- unique(combined$dataset)
  nsamples <- as.numeric(
    stringi::stri_match_last_regex(datasets, "\\(([0-9]+)\\)$")[, 2]
  )
  combined[, dataset := factor(dataset, levels = datasets[order(nsamples, datasets)])]

  # one plot per prediction window, stacked on top of each other
  plot_list <- lapply(
    split(combined, by = "predwindow", sorted = TRUE),
    function(dt) {
      ggplot(
        dt,
        aes(
          cluster_type,
          value,
          color = cluster_type,
          fill = cluster_type
        )
      ) +
        geom_boxplot(
          outlier.shape = 19,
          outlier.size = 1,
          alpha = 0.4,
          linewidth = 0.25
        ) +
        facet_grid(
          rows = vars(error_metric, predwindow),
          cols = vars(dataset),
          scales = "free"
        ) +
        scale_y_continuous(
          trans = "sqrt",
          breaks = scales::breaks_pretty(n = 7)
        ) +
        scale_colour_manual(values = cluster_type_colors) +
        scale_fill_manual(values = cluster_type_colors) +
        theme_bw() +
        theme(
          legend.position = "none",
          legend.title = element_blank(),
          axis.text.x = element_blank(),
          axis.text.y = element_text(size = 12),
          axis.title = element_blank(),
          axis.ticks.x = element_blank(),
          strip.text.x = element_blank(),
          strip.text.y = element_text(size = 10),
          panel.grid.minor = element_blank(),
          panel.grid.major.x = element_blank(),
          panel.grid.major.y = element_line(color = "gray70")
        )
    }
  )

  # dataset names only on the top plot, legend only on the bottom plot
  plot_list[[1]] <- plot_list[[1]] +
    theme(strip.text.x = element_text(angle = 90, size = 12))
  plot_list[[length(plot_list)]] <- plot_list[[length(plot_list)]] +
    theme(
      legend.position = "bottom",
      legend.title = element_text(size = 12),
      legend.text = element_text(size = 14)
    ) +
    labs(color = "Clustering type", fill = "Clustering type")

  plot <- wrap_plots(plot_list, ncol = 1)

  if (isTRUE(save)) {
    ggsave(
      file.path(results_batch_dir, filename),
      plot = plot,
      width = plot_width,
      height = plot_height,
      units = "mm",
      dpi = 600
    )
  }

  invisible(plot)
}

#' @title Read predicted abundance files from a single run
#' @description Read all predicted abundance tables matching a pattern for a single run and combine
#'
#' @param results_dir Path to a results folder as produced by run.bash
#' @param pattern A regex pattern for file names to search for, must end with _<predwindow>.csv
#' @param sample_prefix Prefix for sample names (i.e. true_ or predicted_)
#'
#' @return A (melted) data.table. Sample IDs are prefixed with "<sample_prefix><predwindow>samples_"
read_abund <- function(results_dir, pattern, sample_prefix = "") {
  abund_files <- list.files(
    file.path(results_dir, "data_predicted"),
    pattern = pattern,
    full.names = TRUE
  )

  if (length(abund_files) == 0) {
    stop("No files found for run: \"", results_dir, "\". Unsuccesful run?")
  }
  abund_list <- lapply(
    abund_files,
    function(file) {
      dt <- fread(file, sep = ",", header = TRUE)

      # melt to be able to rowbind all files
      abund <- melt(
        dt,
        id.vars = names(dt)[[1]],
        variable.name = "OTU",
        value.name = "abundance"
      )
      predwindow <- stringi::stri_match_last_regex(file, "_([0-9]+)\\.csv$")[, 2]
      abund[[1]] <- paste0(sample_prefix, predwindow, "samples_", abund[[1]])
      return(abund)
    }
  )

  abund_long <- rbindlist(abund_list)

  # negative abundances doesn't make sense
  n_negative <- abund_long[abundance < 0, .N]
  if (n_negative > 0) {
    warning(n_negative, " negative abundance values have been set to 0")
    abund_long[abundance < 0, abundance := 0]
  }
  return(abund_long)
}

#' @title Read and combine both true and predicted abundance data
#' @description Read and combine real, predicted (train/val/test) and future predicted abundances incl. metadata+taxonomy into a single ampvis2 object.
#' Real samples get a new sample ID prefixed with "true_", predicted samples "pred_<predwindow>samples_" and future ones "future_<predwindow>samples_".
#' The new sample IDs are stored in the first metadata column, which is named as the original sample ID column prefixed with ".", the original sample ID column is kept to pair real and predicted samples.
#'
#' @param results_dir Path to a results folder as produced by run.bash
#' @param cluster_type From which cluster type should the predicted data be from (i.e. abund, func, idec, or graph)
#' @param predwindow Only keep predictions from this prediction window (number of samples predicted ahead). NULL keeps all.
#'
#' @return An ampvis2 class object
combine_abund <- function(results_dir, cluster_type = "graph", predwindow = NULL) {
  cluster_type <- match.arg(tolower(cluster_type), c("abund", "func", "idec", "graph"))
  # avoid clashing with the predwindow column in data.table expressions
  keep_predwindow <- predwindow

  # dates and sample IDs are the same for all files, use as metadata
  metadata <- fread(
    list.files(
      file.path(results_dir, "data_splits"),
      pattern = "dates(_all)?\\.csv$",
      full.names = TRUE
    )[[1]]
  )
  sampleid_col <- colnames(metadata)[[1]]
  new_sampleid_col <- paste0(".", sampleid_col)
  metadata[, (sampleid_col) := as.character(get(sampleid_col))]

  # whether each date is used for train, val, or test
  split_files <- file.path(
    results_dir,
    "data_splits",
    paste0("dates_", c("train", "val", "test"), ".csv")
  )
  splits <- rbindlist(
    lapply(
      split_files[file.exists(split_files)],
      function(file) {
        dt <- fread(file)
        setnames(dt, 1, sampleid_col)
        dt[, (sampleid_col) := as.character(get(sampleid_col))]
        dt[, split_dataset := sub("^dates_(.*)\\.csv$", "\\1", basename(file))]
      }
    )
  )

  if (nrow(splits) > 0) {
    # if using no validation data, it will be identical to test data, remove it
    val_ids <- splits[split_dataset == "val"][[sampleid_col]]
    test_ids <- splits[split_dataset == "test"][[sampleid_col]]
    if (any(val_ids %in% test_ids)) {
      splits <- splits[split_dataset != "val"]
    }
    metadata <- splits[metadata, on = c(sampleid_col, "Date")]
  } else {
    # older versions of the workflow don't write the splits
    metadata[, split_dataset := "predicted"]
  }

  # predicted abundances (from train+val+test)
  pred_abund <- read_abund(
    results_dir = results_dir,
    pattern = paste0("(graph|lstm)_", cluster_type, "_all_predicted_[0-9]+\\.csv$"),
    sample_prefix = "pred_"
  )
  setnames(pred_abund, 1, new_sampleid_col)
  pred_metadata <- unique(pred_abund[, new_sampleid_col, with = FALSE])
  pred_metadata[, (sampleid_col) := sub("^pred_[0-9]+samples_", "", get(new_sampleid_col))]
  pred_metadata[, predwindow := as.integer(sub("^pred_([0-9]+)samples_.*$", "\\1", get(new_sampleid_col)))]
  pred_metadata[, predicted := "predicted"]
  pred_metadata <- metadata[pred_metadata, on = sampleid_col]

  # real abundances (do this AFTER read_abund() to get a meaningful error if the run failed)
  true_abund <- fread(
    list.files(
      file.path(results_dir, "data_predicted"),
      pattern = paste0("(graph|lstm)_", cluster_type, "_all_dataall_nontrans\\.csv$"),
      full.names = TRUE
    )[[1]],
    sep = ",",
    header = TRUE
  )
  setnames(true_abund, 1, new_sampleid_col)
  true_abund[, (new_sampleid_col) := paste0("true_", get(new_sampleid_col))]
  true_abund <- melt(
    true_abund,
    id.vars = new_sampleid_col,
    variable.name = "OTU",
    value.name = "abundance"
  )
  true_metadata <- copy(metadata)
  true_metadata[, (new_sampleid_col) := paste0("true_", get(sampleid_col))]
  true_metadata[, `:=`(split_dataset = "real", predicted = "real", predwindow = 0L)]

  # actual future predictions
  future_abund <- read_abund(
    results_dir = results_dir,
    pattern = paste0("(graph|lstm)_", cluster_type, "_all_actual_prediction_[0-9]+\\.csv$"),
    sample_prefix = "future_"
  )
  setnames(future_abund, 1, new_sampleid_col)
  future_metadata <- unique(future_abund[, new_sampleid_col, with = FALSE])
  future_metadata[, predwindow := as.integer(sub("^future_([0-9]+)samples_.*$", "\\1", get(new_sampleid_col)))]
  future_metadata[, `:=`(predicted = "predicted", split_dataset = "future")]
  # estimate future dates based on the average sampling interval of the real data
  sampling_interval <- as.integer(ceiling(mean(diff(sort(unique(metadata$Date))))))
  future_metadata[, Date := max(metadata$Date) + seq_len(.N) * sampling_interval, by = predwindow]

  abund <- rbindlist(list(true_abund, pred_abund, future_abund))
  metadata <- rbindlist(list(true_metadata, pred_metadata, future_metadata), fill = TRUE)
  metadata[, split_dataset := factor(split_dataset, levels = names(split_dataset_colors))]
  setcolorder(metadata, new_sampleid_col)

  if (!is.null(keep_predwindow)) {
    metadata <- metadata[predwindow %in% c(0L, keep_predwindow)]
    abund <- abund[get(new_sampleid_col) %chin% metadata[[new_sampleid_col]]]
  }

  amp_load(
    otutable = dcast(
      abund,
      as.formula(paste0("OTU ~ `", new_sampleid_col, "`")),
      value.var = "abundance"
    ),
    metadata = metadata,
    taxonomy = file.path(results_dir, "data_reformatted", "taxonomy_wfunctions.csv")
  )
}

#' @title Short readable label for an OTU
#' @description "FLASV3.1527; s__Ca_Microthrix_parvicella; g__Ca_Microthrix" becomes "FLASV3.1527 - Ca. Microthrix parvicella", MiDAS placeholder species are prefixed with the genus, e.g. "FLASV4.1481 - Trichococcus midas_s_4"
#'
#' @param otu Character vector of OTU names as in the taxonomy
#'
#' @return Character vector
otu_label <- function(otu) {
  id <- sub(";.*$", "", otu)
  species <- stringi::stri_match_first_regex(otu, "s__([^;]+)")[, 2]
  genus <- stringi::stri_match_first_regex(otu, "g__([^;]+)")[, 2]
  name <- ifelse(
    grepl("^midas_", species),
    paste(sub("^Ca_", "Ca. ", genus), species),
    gsub("_", " ", sub("^Ca_", "Ca. ", species))
  )
  ifelse(is.na(species), id, paste(id, "-", name))
}

#' @title Time series plot of real and predicted abundances
#'
#' @param data Long format data.table from amp_export_long(combine_abund()) for a single OTU and a single prediction window
#' @param date_limits Range of the x axis, defaults to the range of the data. Set to align stacked plots
#'
#' @return A ggplot object
plot_timeseries <- function(
  data,
  filename = paste0(deparse(substitute(data)), "_timeseries.png"),
  save = TRUE,
  plot_width = 180,
  plot_height = 185,
  add_bg_shades = TRUE,
  date_limits = range(data$Date)
) {
  # from the start of the first quarter to the end of the last
  date_limits <- as.Date(c(
    floor_date(min(date_limits), "3 months"),
    ceiling_date(max(date_limits), "3 months")
  ))
  real <- data[split_dataset == "real"]
  predicted <- data[split_dataset != "real"]

  plot <- ggplot(
    data,
    aes(
      x = Date,
      y = count,
      color = split_dataset
    )
  )

  if (isTRUE(add_bg_shades)) {
    # shade every odd year
    years <- seq(year(date_limits[1]), year(date_limits[2]))
    years <- years[years %% 2 == 1]
    bg_ranges <- data.frame(
      xmin = pmax(make_date(years), date_limits[1]),
      xmax = pmin(make_date(years + 1), date_limits[2])
    )
    plot <- plot +
      geom_rect(
        data = bg_ranges,
        aes(
          xmin = xmin,
          xmax = xmax,
          ymin = -Inf,
          ymax = Inf
        ),
        alpha = 0.15,
        inherit.aes = FALSE,
        show.legend = FALSE
      )
  }

  plot <- plot +
    geom_line(data = real) +
    geom_point(data = real) +
    geom_line(data = predicted, alpha = 0.9) +
    geom_point(data = predicted, alpha = 0.9)

  # mark the start of the test period
  if (any(data$split_dataset == "test", na.rm = TRUE)) {
    plot <- plot + geom_vline(xintercept = min(data[split_dataset == "test", Date]))
  }

  plot <- plot +
    scale_color_manual(
      values = split_dataset_colors,
      labels = split_dataset_labels
    ) +
    # breaks should start from january, regardless of data
    scale_x_date(
      breaks = function(limits) {
        seq(
          from = floor_date(limits[1], "year"),
          to = ceiling_date(limits[2], "year"),
          by = "3 months"
        )
      },
      limits = date_limits,
      date_labels = "%Y %b"
    ) +
    theme(
      legend.position = "bottom",
      legend.title = element_blank(),
      legend.text = element_text(size = 12),
      axis.title.x = element_blank(),
      axis.title.y = element_text(size = 12),
      axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5)
    ) +
    ylab("% Relative Abundance")

  if (isTRUE(save)) {
    ggsave(
      plot,
      file = filename,
      width = plot_width,
      height = plot_height,
      units = "mm",
      dpi = 600
    )
  }

  return(plot)
}

#' @title Scatter plot of real vs. predicted abundances
#' @description Real and predicted samples are paired by the original sample ID. Pairs where either value is 0 are left out.
#' The annotated R^2 values are from a normal linear regression and from the 1:1 line (prediction == real).
#'
#' @param data Long format data.table from amp_export_long(combine_abund()) for a single OTU and a single prediction window. All metadata variables must be kept.
#'
#' @return A ggplot object
plot_obs_pred <- function(data) {
  # the original sample IDs are in the column named as the first column without the leading "."
  sampleid_col <- sub("^\\.", "", colnames(data)[[1]])
  if (!sampleid_col %in% colnames(data)) {
    stop("Column \"", sampleid_col, "\" with the original sample IDs is missing, keep all metadata variables in amp_export_long()")
  }
  # future predictions have no original sample ID
  data <- data[!is.na(get(sampleid_col))]
  if (uniqueN(data$OTU) != 1L) {
    stop("data must contain exactly one OTU")
  }
  if (anyDuplicated(data[, c(sampleid_col, "predicted"), with = FALSE])) {
    stop("data contains more than one prediction window, filter by predwindow first")
  }

  obs_pred <- dcast(
    data,
    as.formula(paste0("`", sampleid_col, "` ~ predicted")),
    value.var = "count"
  )[predicted > 0 & real > 0]

  rsq_lm <- summary(lm(real ~ predicted, data = obs_pred))$r.squared
  rsq_1to1 <- obs_pred[, 1 - sum((real - predicted)^2) / sum((real - mean(real))^2)]

  ggplot(
    obs_pred,
    aes(x = predicted, y = real)
  ) +
    geom_point() +
    geom_abline(slope = 1, intercept = 0) +
    geom_smooth(method = "lm", formula = y ~ x) +
    annotate(
      "text",
      x = -Inf,
      y = Inf,
      label = as.expression(
        bquote(
          atop(
            R^2 == .(round(rsq_lm, 3)),
            R[1:1]^2 == .(round(rsq_1to1, 3))
          )
        )
      ),
      hjust = -0.1,
      vjust = 1,
      size = 4
    ) +
    labs(
      x = "Prediction",
      y = "Real"
    ) +
    tune::coord_obs_pred()
}

#' @title Time series plot next to a real vs. predicted plot
#'
#' @param data Long format data.table from amp_export_long(combine_abund()) for a single OTU and a single prediction window
#' @param title Plot title, defaults to the OTU name
#' @param legend,x_axis,y_title Whether to show the legend, x axis text, and y axis titles. Hide them when stacking plots
#' @param date_limits Passed on to plot_timeseries()
#'
#' @return A patchwork object
plot_ts_obs_pred <- function(
  data,
  title = otu_label(data$OTU[[1]]),
  legend = TRUE,
  x_axis = TRUE,
  y_title = TRUE,
  date_limits = range(data$Date)
) {
  if (uniqueN(data[predwindow > 0, predwindow]) > 1L) {
    stop("data contains more than one prediction window, filter by predwindow first")
  }
  ts <- plot_timeseries(data, save = FALSE, date_limits = date_limits) +
    ggtitle(title) +
    scale_y_continuous(breaks = scales::breaks_pretty(n = 5)) +
    theme(legend.position = if (legend) "bottom" else "none")
  obs_pred <- plot_obs_pred(data)

  if (!x_axis) {
    ts <- ts + theme(axis.text.x = element_blank(), axis.ticks.x = element_blank())
    obs_pred <- obs_pred + theme(axis.title.x = element_blank())
  }
  if (!y_title) {
    ts <- ts + theme(axis.title.y = element_blank())
    obs_pred <- obs_pred + theme(axis.title.y = element_blank())
  }

  ts + obs_pred + plot_layout(widths = c(3, 1))
}

#' @title Stack several plot_ts_obs_pred() plots on top of each other
#' @description All plots share the same x axis, only the bottom plot shows the legend and x axis text, only the middle plot shows y axis titles
#'
#' @param data_list Named list of data.tables, each passed on to plot_ts_obs_pred()
#' @param titles Plot titles, defaults to the list names, or the OTU names if the list is unnamed
#'
#' @return A patchwork object
stack_ts_obs_pred <- function(data_list, titles = names(data_list)) {
  if (is.null(titles)) {
    titles <- vapply(data_list, function(data) otu_label(data$OTU[[1]]), character(1))
  }
  n <- length(data_list)
  date_limits <- range(rbindlist(data_list)$Date)
  plots <- lapply(
    seq_len(n),
    function(i) {
      plot_ts_obs_pred(
        data_list[[i]],
        title = titles[[i]],
        legend = i == n,
        x_axis = i == n,
        y_title = i == ceiling(n / 2),
        date_limits = date_limits
      )
    }
  )
  wrap_plots(plots, ncol = 1)
}

#' @title Split data by prediction window
#' @description Split long format data into one data.table per prediction window, each including the real data
#'
#' @param data Long format data.table from amp_export_long(combine_abund())
#'
#' @return A list of data.tables named e.g. "10 samples ahead"
split_predwindows <- function(data) {
  windows <- sort(unique(data[predwindow > 0, predwindow]))
  setNames(
    lapply(windows, function(w) data[predwindow %in% c(0L, w)]),
    paste(windows, ifelse(windows == 1, "sample", "samples"), "ahead")
  )
}

#' @title Data for a single OTU per prediction window across several runs
#'
#' @param long_list List of long format data.tables from amp_export_long(combine_abund()), e.g. one per run
#' @param otu_regex Regular expression matching a single OTU
#'
#' @return A list of data.tables, see split_predwindows(), sorted by prediction window
predwindow_panels <- function(long_list, otu_regex) {
  panels <- do.call(
    c,
    lapply(long_list, function(long) split_predwindows(long[grepl(otu_regex, OTU)]))
  )
  panels[order(as.integer(sub(" .*$", "", names(panels))))]
}

#' @title Save a figure and the data behind it
#' @description Saves the plot and writes the data to a csv file with the same name
#'
#' @param plot A ggplot or patchwork object
#' @param data A data.frame with the data used for the plot
#' @param path File path to save the plot to, the file extension determines the format
#' @param width,height Size in mm
save_figure <- function(plot, data, path, width = 250, height = 250) {
  ggsave(path, plot = plot, width = width, height = height, units = "mm", dpi = 600)
  fwrite(data, sub("\\.[[:alnum:]]+$", ".csv", path))
}

#' @title PCoA of real and predicted samples
#' @description Real and predicted samples from the same date are connected by a line. Future predictions are left out.
#'
#' @param results_dir Path to a results folder as produced by run.bash
#' @param cluster_type,predwindow Passed on to combine_abund()
#'
#' @return A ggplot object
plot_pcoa <- function(results_dir, cluster_type = "graph", predwindow = 10) {
  data <- combine_abund(results_dir, cluster_type = cluster_type, predwindow = predwindow)
  data <- amp_filter_samples(data, split_dataset != "future")

  amp_ordinate(
    data,
    type = "pcoa",
    distmeasure = "bray",
    transform = "none",
    filter_species = 0,
    sample_color_by = "split_dataset",
    sample_trajectory = "Date",
    sample_trajectory_group = "Date"
  ) +
    scale_color_manual(
      values = split_dataset_colors,
      labels = split_dataset_labels
    ) +
    scale_x_continuous(breaks = scales::breaks_pretty(n = 3)) +
    scale_y_continuous(breaks = scales::breaks_pretty(n = 3)) +
    theme(
      legend.title = element_blank(),
      legend.text = element_text(size = 16),
      axis.text = element_text(size = 16),
      axis.title = element_text(size = 16),
      legend.position = "bottom"
    ) +
    guides(color = guide_legend(nrow = 2)) +
    coord_fixed(ratio = 1)
}

#' @title Plot a graph adjacency matrix from the graph model
#'
#' @param graph_matrix_file Path to a csv file in the graph_matrix subfolder of a results folder
#' @param plot_title Plot title, defaults to the file name
#'
#' @return A ggplot object
plot_graph <- function(
  graph_matrix_file,
  plot_title = gsub("^.*/|\\.csv$", "", graph_matrix_file)
) {
  graph_cluster <- fread(
    graph_matrix_file,
    header = TRUE,
    data.table = FALSE
  )
  rownames(graph_cluster) <- graph_cluster[[1]]
  graph_cluster <- graph_cluster[, -1, drop = FALSE]
  graph_cluster[] <- lapply(graph_cluster, round, 3)
  graph_cluster[graph_cluster == 0] <- 0.001 #pseudo-zero

  graph <- igraph::graph_from_adjacency_matrix(
    as.matrix(graph_cluster),
    mode = "undirected",
    weighted = TRUE,
    diag = FALSE
  ) |>
    tidygraph::as_tbl_graph(directed = FALSE)

  # use non-negative values for the layout, but keep originals for labels
  igraph::E(graph)$weight.orig <- igraph::E(graph)$weight
  igraph::E(graph)$weight <- abs(igraph::E(graph)$weight)

  colors <- rev(RColorBrewer::brewer.pal(n = 3, name = "RdBu"))

  # GEM force-directed layout
  ggraph::ggraph(
    graph,
    layout = "igraph",
    algorithm = "gem"
  ) +
    ggraph::geom_edge_link(
      aes(
        label = weight.orig,
        color = weight.orig
      ),
      width = 2,
      show.legend = FALSE
    ) +
    ggraph::geom_node_point(size = 3) +
    ggraph::geom_node_label(
      aes(label = name),
      repel = TRUE
    ) +
    ggraph::scale_edge_color_gradient2(
      low = colors[1],
      mid = "grey80",
      high = colors[3],
      guide = "none"
    ) +
    theme_void() +
    ggtitle(plot_title)
}

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
  files <- list.files(
    results_dir,
    pattern = ".*_performance.txt",
    full.names = TRUE
  )
  list <- lapply(
    files,
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
    scale_color_brewer(palette = "Set2") +
    facet_grid(rows = vars(errorfunc), cols = vars(clustertype)) +
    ylim(0, 1)
  print(plot)
  cluster_info_file <- file.path(results_dir, "clusters.txt")
  if(file.exists(cluster_info_file))
    cli::cat_line(readLines(cluster_info_file))
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
#' @description Read and parse a performance summary {lstm,graph}_{idec,abund,func,graph}_performance.txt file and return as data table
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
#' @param add_dataset_info If TRUE paste the number of predicted samples to each dataset. If FALSE show the number of samples instead.
#'
#' @return A data.table
#' @export
#'
#' @examples
read_performance <- function(
  results_dir,
  add_dataset_info = c(
    "numsamples",
    "predwindow",
    "noneorwhateverelse"
  )[1]
) {
  filenames <- c(
    "lstm_idec_performance.txt",
    "lstm_abund_performance.txt",
    "lstm_func_performance.txt",
    "graph_idec_performance.txt",
    "graph_abund_performance.txt",
    "graph_func_performance.txt",
    "graph_graph_performance.txt"
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
      full.names = TRUE
    ),
    sep = "\n",
    header = FALSE,
    col.names = "line"
  )

  dt$dataset <- basename(
    gsub(
      "reformatted|data|ASVtable.*$|otutable.*$",
      "",
      logfile[grepl("abund_file", line)]
    )
  )

  #read metadata to get the number of samples to append dataset names
  metadata <- fread(
    file.path(results_dir, "data_reformatted", "metadata.csv")
  )

  if (length(add_dataset_info) != 1) {
    if(!is.character(add_dataset_info)) {
      stop("add_dataset_info must be a character vector of length 1")
    }
  }

  if (add_dataset_info == "numsamples") {
    dt$dataset <- paste0(dt$dataset, " (", nrow(metadata), ")")
  } else if(add_dataset_info == "predwindow") {
  dt$dataset <- paste0(
    dt$dataset,
    " (",
    gsub(
      "[^0-9]*",
      "",
      logfile[grepl("predict_timestamp", line), line]),
      " P.S.)"
    )
  }

  dt$cluster_type <- stringr::str_replace_all(
    dt$cluster_type,
    pattern = c(
      "lstm_abund" = "Ranked abundance",
      "lstm_func" = "Biological function",
      "lstm_idec" = "IDEC",
      "graph_abund" = "Ranked abundance",
      "graph_func" = "Biological function",
      "graph_idec" = "IDEC",
      "graph_graph" = "Graph"
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
#' @description Read all performance summary files from a batch of multiple runs (i.e. WWTPs) and plot a summary boxplot. Will also save the plot to a PDF file in each folder.
#'
#' @param results_batch_dir Path to a folder containing one or more subfolders, each produced by run.bash (i.e. produced by loop_datasets.bash)
#'
#' @return A ggplot2 object
#' @export
#'
#' @examples
boxplot_all <- function(
  results_batch_dir,
  add_dataset_info = "numsamples",
  filename = "boxplot_all.png",
  save = TRUE,
  plot_width = 180,
  plot_height = 185
) {
  runs <- list.dirs(
    results_batch_dir,
    full.names = TRUE,
    recursive = FALSE
  )
  if (length(runs) == 0) {
    stop("No results folders found, wrong working directory?")
  }

  d_list <- lapply(runs, read_performance, add_dataset_info)
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
            rows = vars(error_metric),
            cols = vars(dataset),
            scales = "free"
          ) +
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
          ) +
          scale_colour_manual(values = cluster_type_colors) +
          scale_fill_manual(values = cluster_type_colors)
      }
    )

  # The first plot will be at the top and show facet strips but no x axis text
  # Bray-Curtis axis breaks must be set between 0 - 1
  plot_list[[1]] <- plot_list[[1]] +
    theme(
      axis.ticks.x = element_blank(),
      strip.text.x = element_text(angle = 90, size = 12)
    ) +
    scale_y_continuous(
      trans = "sqrt",
      breaks = breaks_pretty(n = 7)
    )

  # Increase the number of axis breaks for the middle plot
  plot_list[[2]] <- plot_list[[2]] +
  scale_y_continuous(
    trans = "sqrt",
    breaks = breaks_pretty(n = 7)
  )

  # The last plot will be at the bottom and
  # show no facet strips but will show x axis text
  # increase the number of axis breaks
  plot_list[[length(plot_list)]] <- plot_list[[length(plot_list)]] +
    theme(
      strip.text.x = element_blank(),
      legend.position = "bottom",
      legend.title = element_text(size = 12),
      legend.text = element_text(size = 14)
    ) +
    scale_y_continuous(
      trans = "sqrt",
      breaks = breaks_pretty(n = 7)
    ) +
    labs(color = "Clustering type", fill = "Clustering type")

  # Compose all plots in the list using patchwork
  plot <- purrr::reduce(
    plot_list,
    `/`
  )

  if(isTRUE(save)) {
    ggsave(
      file.path(dirname(combined[1, results_folder]), filename),
      plot = plot,
      width = plot_width,
      height = plot_height,
      units = "mm",
      dpi = 600
    )
  }

  invisible(plot_list)
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

  if (length(abund_files) == 0) {
    stop("No files found for run: \"", results_dir, "\". Unsuccesful run?")
  }
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
        id.vars = names(file)[[1]],
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
    OTU~eval(parse(text = colnames(abund_dt)[1])),
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
  cluster_types <- c("abund", "func", "idec", "graph")
  if (length(cluster_type) != 1L || !any(cluster_type %in% cluster_types)) {
    stop(
      "cluster_type must be one of: ",
      paste0(cluster_types, collapse = ", "))
  }
  #read predicted abundance tables
  pred_abund <- read_abund(
    results_dir = results_dir,
    pattern = paste0("(graph|lstm)_", cluster_type, "_cluster_.+_predicted\\.csv$"),
    sample_prefix = "pred_"
  )

  #read true abundance tables
  true_abund <- read_abund(
    results_dir = results_dir,
    pattern = paste0("(graph|lstm)_", cluster_type, "_cluster_.+_dataall_nontrans\\.csv$"),
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
  sampleid_col <- names(metadata)[[1]]

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
        metadata_split_datasets[split_dataset == "val"][[sampleid_col]] %chin%
        metadata_split_datasets[split_dataset == "test"][[sampleid_col]]
      )
    ) {
      metadata_split_datasets <- metadata_split_datasets[split_dataset != "val"]
    }
    metadata <- metadata_split_datasets[metadata, on = c(sampleid_col, "Date")]
  } else if (sum(dim(metadata_split_datasets)) == 0L) {
    metadata[, split_dataset := "predicted"]
  }

  #load predicted and true data
  predicted_data <- amp_load(
    otutable = pred_abund,
    metadata = metadata[
      ,
      .(
        Sample = paste0("pred_", eval(parse(text = sampleid_col))),
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
        Sample = paste0("true_", eval(parse(text = sampleid_col))),
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

  # Order dataset type (split_dataset) by real-train-val-test
  combined$metadata$split_dataset <- factor(
    combined$metadata$split_dataset,
    levels = c("real", "train", "val", "test")
  )

  return(combined)
}


plot_timeseries <- function(
  data,
  filename = paste0(deparse(substitute(data)), "_timeseries.png"),
  save = TRUE,
  plot_width = 180,
  plot_height = 185
) {
  #generate a data frame with x coordinates for
  #alternating background shades for each year
  bg_ranges <- data.frame(
    xmin = seq(
      from = floor_date(min(data$Date), "year"),
      to = floor_date(max(data$Date), "year"),
      by = "2 years"
    ),
    xmax = seq(
      from = floor_date(min(data$Date), "year"),
      to = floor_date(max(data$Date), "year"),
      by = "2 years"
    ) + years(1)
  )

  #always start at odd years, if data starts at an even year
  #add 1 year and delete the last row to skew
  if (year(min(bg_ranges$xmin)) %% 2 == 0) {
    bg_ranges[] <- lapply(bg_ranges, `+`, years(1))
    bg_ranges[-nrow(bg_ranges), ]
  }

  plot <- ggplot(
  data,
  aes(
    x = Date,
    y = count,
    color = split_dataset
  )
) +
  geom_line(data = data[split_dataset == "real"]) +
  geom_point(data = data[split_dataset == "real"]) +
  geom_line(data = data[split_dataset != "real"], alpha = 0.9) +
  geom_point(data = data[split_dataset != "real"], alpha = 0.9) +
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
  ) +
  geom_vline(xintercept = data[split_dataset == "test", min(Date)]) +
  scale_color_manual(
    values = c(
      "black",
      "#bd2929",
      "#e0b01c",
      "#16a085"
    )[1:data[, length(unique(split_dataset))]],
    labels = c(
      real = "Real",
      train = "Prediction-Train",
      val = "Prediction-Validation",
      test = "Prediction-Test"
    )[1:data[, length(unique(split_dataset))]],
    breaks = c(
      "real",
      "train",
      "val",
      "test"
    )[1:data[, length(unique(split_dataset))]]
  ) +
  #breaks should start from january, regardless of data
  scale_x_date(
    breaks = function(limits) {
      seq(
        from = floor_date(limits[1], "year"),
        to = ceiling_date(limits[2], "year"),
        by = "3 months"
      )
    },
    date_labels =  "%Y %b"
  ) +
  theme(
    legend.position = "bottom",
    legend.title = element_blank(),
    legend.text = element_text(size = 10),
    axis.title.x = element_blank(),
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

plot_obs_pred <- function(ampvis2_long) {
  # cast dataset
  carsten <- dcast(
    ampvis2_long[, Sample := gsub("true_|pred_", "", Sample)],
    Sample + OTU ~ predicted,
    value.var = "count"
  )[!is.na(predicted)]

  #calc trendline/regression between obs+pred for each OTU
  trendy_carsten <- carsten[
    ,
    {
      ss_total <- sum((real - mean(real))^2) # Total sum of squares
      ss_residual <- sum((real - predicted)^2) # Residual sum of squares compared to 1:1 line
      rsq <- 1 - (ss_residual / ss_total) # R-squared for the 1:1 line
      model = lm(predicted ~ real) # normal linear regression model
      list(
        rsq_1to1 = rsq,
        lm_intercept = coef(model)[[1]],
        lm_slope = coef(model)[[2]],
        lm_rsq = summary(model)$r.squared
      )
    },
    by = OTU
  ]
  d <- carsten
  ggplot(
    d,
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
            R^2 == .(round(trendy_carsten$lm_rsq, 3)),
            R[1:1]^2 == .(round(trendy_carsten$rsq_1to1, 3))
          )
        )
      ),
      hjust = -0.1,
      vjust = 1,
      size = 3
    ) +
    labs(
      x = "Prediction",
      y = "Real"
    ) +
    #coord_fixed() +
    #theme(aspect.ratio = 1) +
    tune::coord_obs_pred()
}

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

  graph <- graph_cluster %>%
    as.matrix %>%
    graph.adjacency(
      mode = "undirected",
      weighted = TRUE,
      diag = FALSE
    ) %>%
    as_tbl_graph(directed = FALSE)

  #use non-negative values for the layout, but keep originals for labels
  E(graph)$weight.orig <- E(graph)$weight
  E(graph)$weight <- abs(E(graph)$weight)

  #Fruchterman-Reingold layout graph
  ggraph(
    graph,
    layout = "igraph",
    algorithm = "gem"
  ) +
    geom_edge_link(
      aes(
        label = weight.orig,
        color = weight.orig
      ),
      width = 2,
      show.legend = FALSE
    ) +
    geom_node_point(size = 3) +
    geom_node_label(
      aes(label = name),
      repel = TRUE
    ) + {
      colors <- rev(RColorBrewer::brewer.pal(n = 3, name = "RdBu"))
      scale_edge_color_gradient2(
        low = colors[1],
        mid = "grey80",
        high = colors[3],
        breaks = c(-Inf, 0, Inf),
        #labels = c("Negative", "Zero", "Positive")
      )
    } +
    theme_void() +
    ggtitle(plot_title)
}

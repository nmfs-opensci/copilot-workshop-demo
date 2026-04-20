library(shiny)
library(leaflet)
library(rerddap)
library(surveyjoin)
library(viridis)
library(dplyr)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

#' Return available SST dates from the ERDDAP dataset metadata.
#' Returns a character vector of "YYYY-MM-DD" strings, or NULL on failure.
get_erddap_dates <- function() {
  tryCatch({
    info_obj <- info("ncdcOisst21Agg_LonPM180",
                     url = "https://coastwatch.pfeg.noaa.gov/erddap/")
    time_meta <- info_obj$alldata$time
    # actual_range row contains "start, end" epoch seconds
    range_row  <- time_meta[time_meta$attribute_name == "actual_range", "value"]
    # nValues row gives the count and spacing
    nval_row   <- time_meta[time_meta$attribute_name == "" &
                              grepl("nValues", time_meta$value), "value"]

    # Parse start / end from actual_range  (two doubles separated by ", ")
    parts <- as.numeric(strsplit(trimws(range_row), ",\\s*")[[1]])
    t_start <- as.Date(as.POSIXct(parts[1], origin = "1970-01-01", tz = "UTC"))
    t_end   <- as.Date(as.POSIXct(parts[2], origin = "1970-01-01", tz = "UTC"))

    seq(t_start, t_end, by = "day")
  }, error = function(e) {
    NULL
  })
}

#' Fetch SST for a single date and match it to the nwfsc_grid points.
#' @param grid   data.frame with columns lon, lat (NWFSC.Combo subset)
#' @param date   Date object
#' @return data.frame: grid with an added "sst" column, or NULL on failure
fetch_sst <- function(grid, date) {
  tryCatch({
    lon_range <- range(grid$lon, na.rm = TRUE)
    lat_range <- range(grid$lat, na.rm = TRUE)
    date_str  <- format(date, "%Y-%m-%d")

    raw <- griddap(
      "ncdcOisst21Agg_LonPM180",
      url       = "https://coastwatch.pfeg.noaa.gov/erddap/",
      time      = c(date_str, date_str),
      longitude = lon_range,
      latitude  = lat_range,
      fields    = "sst"
    )

    sst_df <- raw$data
    if (is.null(sst_df) || nrow(sst_df) == 0) return(NULL)

    # Rename to common column names
    names(sst_df) <- tolower(names(sst_df))
    sst_df <- sst_df[, c("longitude", "latitude", "sst")]
    sst_df <- sst_df[!is.na(sst_df$sst), ]

    # For each grid point find the nearest SST raster cell
    # (vectorised nearest-neighbour via outer difference)
    matched_sst <- vapply(seq_len(nrow(grid)), function(i) {
      dx  <- (sst_df$longitude - grid$lon[i])^2
      dy  <- (sst_df$latitude  - grid$lat[i])^2
      idx <- which.min(dx + dy)
      if (length(idx) == 0) NA_real_ else sst_df$sst[idx]
    }, numeric(1))

    grid$sst <- matched_sst
    grid
  }, error = function(e) {
    message("fetch_sst error: ", conditionMessage(e))
    NULL
  })
}

# ---------------------------------------------------------------------------
# Pre-load static data (runs once at startup)
# ---------------------------------------------------------------------------

nwfsc <- surveyjoin::nwfsc_grid
nwfsc <- nwfsc[nwfsc$survey == "NWFSC.Combo", ]
nwfsc$cell_id <- seq_len(nrow(nwfsc))

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

ui <- fluidPage(
  titlePanel("NWFSC Survey Grid – Sea Surface Temperature"),

  sidebarLayout(
    sidebarPanel(
      width = 3,
      h4("Select a Date"),
      uiOutput("date_ui"),
      br(),
      actionButton("fetch_btn", "Fetch SST", class = "btn-primary"),
      br(), br(),
      helpText(
        "Points are colored by SST (°C) using the viridis palette.",
        "Click a point to see its Mean SST and Grid Cell ID."
      ),
      br(),
      verbatimTextOutput("status_msg")
    ),

    mainPanel(
      width = 9,
      leafletOutput("map", height = "80vh")
    )
  )
)

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

server <- function(input, output, session) {

  # -- Fetch available dates once per session --------------------------------
  available_dates <- reactive({
    withProgress(message = "Loading available dates…", value = 0.3, {
      d <- get_erddap_dates()
      if (is.null(d)) {
        showNotification(
          "Could not retrieve date range from ERDDAP. Using last 30 days as fallback.",
          type = "warning", duration = 10
        )
        d <- seq(Sys.Date() - 30, Sys.Date(), by = "day")
      }
      d
    })
  })

  # -- Render date picker ----------------------------------------------------
  output$date_ui <- renderUI({
    dates <- available_dates()
    dateInput(
      "sel_date",
      label   = NULL,
      value   = max(dates) - 1L,   # default: most-recent minus 1 (often available)
      min     = min(dates),
      max     = max(dates)
    )
  })

  # -- Base leaflet map (rendered once) --------------------------------------
  output$map <- renderLeaflet({
    leaflet() %>%
      addTiles() %>%
      setView(lng = -125, lat = 46, zoom = 5)
  })

  # -- Status message --------------------------------------------------------
  status <- reactiveVal("")
  output$status_msg <- renderText(status())

  # -- Fetch SST on button click ---------------------------------------------
  sst_data <- eventReactive(input$fetch_btn, {
    req(input$sel_date)

    sel_date <- as.Date(input$sel_date)

    # Validate against available dates
    dates <- available_dates()
    if (!is.null(dates) && !sel_date %in% dates) {
      status(paste0(
        "Date ", sel_date,
        " is not available on the ERDDAP server. Please choose another date."
      ))
      return(NULL)
    }

    status("Fetching SST data…")

    result <- withProgress(message = "Fetching SST from ERDDAP…", value = 0.5, {
      fetch_sst(nwfsc, sel_date)
    })

    if (is.null(result)) {
      status(paste0(
        "No SST data found for ", sel_date,
        ". Please choose another date."
      ))
      return(NULL)
    }

    status(paste0("SST loaded for ", sel_date,
                  " (", sum(!is.na(result$sst)), " points)."))
    result
  })

  # -- Update map whenever sst_data changes ----------------------------------
  observe({
    df <- sst_data()
    req(!is.null(df), nrow(df) > 0)

    df_valid <- df[!is.na(df$sst), ]
    if (nrow(df_valid) == 0) return()

    sst_vals <- df_valid$sst
    pal <- colorNumeric(
      palette = viridis(256),
      domain  = sst_vals,
      na.color = "transparent"
    )

    leafletProxy("map", data = df_valid) %>%
      clearMarkers() %>%
      clearControls() %>%
      addCircleMarkers(
        lng    = ~lon,
        lat    = ~lat,
        radius = 4,
        color  = ~pal(sst),
        stroke = FALSE,
        fillOpacity = 0.85,
        popup  = ~paste0(
          "<b>Grid Cell ID:</b> ", cell_id, "<br>",
          "<b>Mean SST:</b> ", round(sst, 2), " °C<br>",
          "<b>Lon:</b> ", round(lon, 3), "<br>",
          "<b>Lat:</b> ", round(lat, 3)
        )
      ) %>%
      addLegend(
        position = "bottomright",
        pal      = pal,
        values   = sst_vals,
        title    = "SST (°C)",
        opacity  = 0.85
      )
  })
}

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------

shinyApp(ui = ui, server = server)

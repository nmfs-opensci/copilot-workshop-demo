# NWFSC Survey Grid SST Shiny App

An R Shiny application that visualises **Mean Sea Surface Temperature (SST)**
on NWFSC trawl-survey grid points along the US West Coast.

---

## What it does

* Loads the NWFSC Combo survey grid (lat/lon points) from the
  [`surveyjoin`](https://github.com/DFO-NOAA-Pacific/surveyjoin) package.
* Fetches daily SST from the NOAA CoastWatch ERDDAP server
  (dataset `ncdcOisst21Agg_LonPM180`) for any date the user selects.
* Displays an interactive **Leaflet** map centred on the WA/OR coast.
* Colours each grid point by its SST value using the **viridis** palette and
  shows a colour legend.
* Clicking a point opens a popup with the **Grid Cell ID** and **Mean SST (°C)**.
* Gracefully handles unavailable dates with an informative message instead of
  crashing.

---

## Required packages

| Package | Source |
|---------|--------|
| `shiny` | CRAN |
| `leaflet` | CRAN |
| `rerddap` | CRAN |
| `viridis` | CRAN |
| `dplyr` | CRAN |
| `surveyjoin` | GitHub – `DFO-NOAA-Pacific/surveyjoin` |

---

## Installation

### 1 – Install system libraries (Linux / Ubuntu)

```bash
sudo apt-get update
sudo apt-get install -y libcurl4-openssl-dev libssl-dev libxml2-dev \
  libgdal-dev libgeos-dev libproj-dev libudunits2-dev
```

### 2 – Install R packages

```r
install.packages("pak", repos = "https://r-lib.github.io/p/pak/dev/")
pak::pkg_install(c("shiny", "leaflet", "rerddap", "dplyr", "viridis"))
pak::pkg_install("DFO-NOAA-Pacific/surveyjoin")
```

---

## Running the app

### From the R console

```r
shiny::runApp("app.R")
```

### From the command line

```bash
Rscript -e "shiny::runApp('app.R')"
```

The app will open in your default browser.  
If it does not open automatically, navigate to the URL shown in the console
(e.g. `http://127.0.0.1:XXXX`).

---

## Using the app

1. The date picker is pre-populated with the full range of dates available on
   the ERDDAP server.  Select a date and click **Fetch SST**.
2. Grid points will appear on the map coloured by SST.
3. Click any point to see its **Grid Cell ID** and **Mean SST (°C)** in a popup.
4. If the selected date has no data on the server a message is displayed in the
   sidebar – simply choose another date.

---

## Data sources

* **SST** – NOAA OISSTv2.1 daily composites via ERDDAP  
  Dataset ID: `ncdcOisst21Agg_LonPM180`  
  URL: <https://coastwatch.pfeg.noaa.gov/erddap/>
* **Survey grid** – `surveyjoin::nwfsc_grid` (NWFSC.Combo survey)

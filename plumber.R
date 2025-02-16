library(dplyr)
library(glue)
library(here)
library(plumber)
library(stringr)

source(here("../workflows/libs/db.R")) # define: con

#* @apiTitle MarineSensitivity Custom API

# /species_by_feature ----
#* Output a table of species present from one or more spatial feature(s)
#* - The output is in comma-separated format (*.csv).
#* - Species are extracted from [AquaMaps.org](https://www.aquamaps.org) (and more specifically
#* [aquamapsdata](https://raquamaps.github.io/aquamapsdata/articles/intro.html#data-scope-and-content-1)).
#* - For available features on the server by which to query, see spatial **Table Layers** listed at
#* [tile.marinesensitivity.org](https://tile.marinesensitivity.org).
#* @param schema.table The SCHEMA.TABLE containing the feature(s).
#* @param where The WHERE clause selecting the feature(s) as the area of interest.
#* @serializer csv
#* @get /species_by_feature
function(
    schema.table = "raw.mr_eez",
    where        = "mrgid = 8442"){

  # schema.table = "public.ply_ecoareas"
  # where        = "ecoarea_key = 'erCAC-paCEC'"

  schema <- str_split(schema.table, fixed("."))[[1]][1]
  table  <- str_split(schema.table, fixed("."))[[1]][2]

  fld_geom <- dbGetQuery(
    con,
    glue("
      SELECT f_geometry_column
      FROM geometry_columns
      WHERE
        f_table_schema = '{schema}' AND
        f_table_name   = '{table}';")) |>
    pull(f_geometry_column)
  # message(glue("schema.table: '{schema}.{table}'; fld_geom: '{fld_geom}'"))

  q <- glue("
    WITH
      c AS (
        SELECT
        c.cell_id,
        c.area_km2 AS cell_km2,
        CASE
          WHEN ST_CoveredBy(c.geom, a.{fld_geom})
            THEN c.geom
          ELSE
            ST_Multi(ST_Intersection(c.geom, a.{fld_geom}))
        END AS geom
      FROM
        aquamaps.cells c
        INNER JOIN {table} a
          ON ST_Intersects(c.geom, a.{fld_geom})
            AND NOT ST_Touches(c.geom, a.{fld_geom})
      WHERE
        a.{where}
      ORDER BY
        c.cell_id),
    k AS (
      SELECT *,
        ST_AREA(geom::geography) / (1000 * 1000) AS aoi_km2
      FROM c),
    a AS (
      SELECT *,
        aoi_km2 / cell_km2 AS pct_cell
      FROM k),
    s AS (
      SELECT a.*,
        sc.sp_key, sc.probability
      FROM a
        LEFT JOIN aquamaps.spp_cells sc
          ON a.cell_id = sc.cell_id),
    g AS (
      SELECT
        sp_key,
        COUNT(*)                                  AS n_cells,
        AVG(pct_cell)                             AS avg_pct_cell,
        SUM(aoi_km2)                              AS area_km2,
        SUM(probability * aoi_km2) / SUM(aoi_km2) AS avg_suit
      FROM s
      GROUP BY sp_key)
    SELECT
      sp_key, n_cells, avg_pct_cell, area_km2, avg_suit,
      n_cells * avg_pct_cell * avg_suit AS amt,
      phylum, class, \"order\", family, genus, species
    FROM
      g
      LEFT JOIN aquamaps.spp USING (sp_key)")
  # message(q)

  dbGetQuery(con, q)
}


# /echo ----
#* Echo back the input
#* @param msg The message to echo
#* @get /echo
function(msg=""){
  list(msg = paste0("The message is: '", msg, "'"))
}

# /plot ----
#* Plot a histogram
#* @serializer png
#* @get /plot
function(){
  rand <- rnorm(100)
  hist(rand)
}

# /sum ----
#* Return the sum of two numbers
#* @param a The first number to add
#* @param b The second number to add
#* @post /sum
function(a, b){
  as.numeric(a) + as.numeric(b)
}

# / home ----
#* redirect to the swagger interface
#* @get /
#* @serializer html
function(req, res) {
  res$status <- 303 # redirect
  res$setHeader("Location", "./__swagger__/")
  "<html>
  <head>
    <meta http-equiv=\"Refresh\" content=\"0; url=./__swagger__/\" />
  </head>
  <body>
    <p>For documentation on this API, please visit <a href=\"http://api.ships4whales.org/__swagger__/\">http://api.ships4whales.org/__swagger__/</a>.</p>
  </body>
</html>"
}

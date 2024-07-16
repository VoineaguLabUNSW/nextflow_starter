process NUMERIC_COLS {
    conda "conda-forge::r-base==4.1.2"

    input:
    tuple path(csv), val(x)

    output:
    tuple path(csv), val(x), stdout

    script:
    """
    #!/usr/bin/env Rscript
    data <- read.csv("$csv")
    numeric_cols <- colnames(data)[unlist(lapply(data, is.numeric), use.names=FALSE)]
    cat(paste(numeric_cols, collapse = ','))
    """
}

process PLOT_COL {
    publishDir "results", mode: 'symlink'
    conda 'r-ggplot2'

    input:
    tuple path(csv), val(x), val(y)

    output:
    path "*.png"

    script:
    """
    #!/usr/bin/env Rscript
    library(ggplot2)
    data <- read.csv("$csv")
    ggplot(data, aes(x=$x, y=$y)) + geom_point()
    ggsave("${x}_vs_${y}.png")
    """
}

workflow {
    input = Channel.of(new Tuple("https://raw.githubusercontent.com/selva86/datasets/master/midwest.csv", "percollege"))
    numeric_comma_sep = NUMERIC_COLS(input)
    numeric_flat = numeric_comma_sep.map(v -> v[2].split(',').collect {new Tuple(v[0], v[1], it)}).flatMap()
    PLOT_COL(numeric_flat)
}
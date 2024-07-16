process NUMERIC_COLS {
    conda "conda-forge::r-base==4.1.2"

    input:
    path my_csv

    output:
    stdout

    script:
    """
    #!/usr/bin/env Rscript
    data <- read.csv("$my_csv")
    numeric_cols <- colnames(data)[unlist(lapply(data, is.numeric), use.names=FALSE)]
    cat(paste(numeric_cols, collapse = ','))
    """
}

workflow {
    my_csvs = Channel.of("https://raw.githubusercontent.com/selva86/datasets/master/midwest.csv")

    numeric_cols = NUMERIC_COLS(my_csvs)
    
    numeric_cols.view()
    // outputs: PID,area,poptotal,popdensity,popwhite,popblack,popamerindian,...    (incorrect)

    numeric_cols.map{it.split(',')}.flatten().view()
    // outputs: PID                                                                 (correct)
    //          area
    //          poptotal
}
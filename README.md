# Nextflow Starter
## Scatter Gather Explained Using Three Examples

This guide will focus on the scatter-gather method for "embarrassingly parallel" tasks. Most Nextflow introductions tend to gloss over manipulating channels beyond the built-in methods. To have any intuition when architecting your own workflow (or reading a published one), the built-in methods are important - but using map/flatten/flatMap/collect, we can achieve almost anything.

Nextflow workflows are made up of process blocks and workflow blocks connecting them - but instead of long definitions, it's best to just look at examples. Note the examples below can be copied and run in a single .nf file, but in practice you may want to use a nextflow.config file instead of specifying NXF_CONDA_ENABLED etc. each time, as well as split your processes into different files.

### What you should learn:
- processes (input, output, script, publishdir)
- channel operators (flatten, map, flatMap, gather)
- basic process dependency definitions (conda)
- resource process definitions (cpus, memory)

## Scatter (one-to-many)

This pattern is seen in any bioinformatics workflow that starts with a single samplesheet file and then each line kicks off an independant analysis. You will see that all one-to-many operations require the [flatten operator](https://www.nextflow.io/docs/latest/operator.html#flatten), some other in-built channel operator, or [each](https://www.nextflow.io/docs/latest/process.html#input-repeaters-each).

### Example 1. WRITE_GREETINGS

The most basic Nextflow guides deal entirely with files. If a process outputs multiple files, a single list is emitted along the channel. In many cases, you want to write a downstream process that runs a computationally heavy operation on each file separately, so we "flatten" the channel - i.e. for each list that comes down the pipe, we instead emit each item separately. Although it looks like we are calling functions in the workflow block, we are really connecting asynchronous pipes.

> [!WARNING]
> In this case Nextflow uses whatever Python version is installed.

```go
process WRITE_GREETINGS {
    output:
    path "*.txt"

    script:
    """
    #!/usr/bin/env python
    for greeting in ['hello', 'hi']:
        with open(greeting + '.txt', 'w') as f:
            f.write(greeting)
    """
}

process HEAVY_COMPUTATION {
    input:
    path my_path

    script:
    """
    #!/usr/bin/env bash
    sleep 10
    cat "$my_path"
    """
}

workflow {
    greetings = WRITE_GREETINGS()

    greetings.view()
    //outputs:   [.../work/.../hello.txt, .../work/.../hi.txt]
    
    greetings.flatten().view() 
    //outputs:   .../work/.../hello.txt
    //           .../work/.../hi.txt 

    HEAVY_COMPUTATION(greetings.flatten())

    println("done")
    //outputs: done     (BEFORE anything above prints!)
}
```

Note when we call `greetings.view()` and `greetings.flatten()` and `HEAVY_COMPUTATION(greetings.flatten())` the channel is automatically split so that all downstream processes receive each emission.

### Example 2. NUMERIC_COLS

Lets do this one-to-many operation again, except instead of emitting a list, our process emits a comma-separated string. Using R this time, we read the csv (which Nextflow automatically converts/caches to a path since we are using a URL), and print our numeric columns to standard output.

> [!TIP]
> Run using `NXF_CONDA_ENABLED=true nextflow run main.nf` if you have conda but not R installed.
> Does not work with mamba/micromamba, but you should enable the mamba solver using `conda config --set solver libmamba` and may need `conda config --set channel_priority flexible`.


```go
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
```

This approach is fine, but if we supply multiple datasets, we no longer know which column came from where. This is a major difference between "tutorial" workflows and one you might read from nf-core - the frequent use of tuples that passthrough some sort of identifier (to support, for example, single AND paired-end reads in one workflow). Note here that flatten emits EVERYTHING one at a time, wheras we only want to flatten at the top level but keep the pairs intact. The [flatMap operator](https://www.nextflow.io/docs/latest/operator.html#flatmap) allows this.

```go
process NUMERIC_COLS_TUPLE {
    conda "conda-forge::r-base==4.1.2"

    input:
    path my_csv

    output:
    tuple path(my_csv), stdout

    script:
    """
    #!/usr/bin/env Rscript
    data <- read.csv("$my_csv")
    numeric_cols <- colnames(data)[unlist(lapply(data, is.numeric), use.names=FALSE)]
    cat(paste(numeric_cols, collapse = ','))
    """
}

workflow {
    my_csvs = Channel.of("https://raw.githubusercontent.com/selva86/datasets/master/midwest.csv", "https://raw.githubusercontent.com/selva86/datasets/master/livestock.csv")

    numeric_cols = NUMERIC_COLS_TUPLE(my_csvs)

    numeric_cols.view()
    // output:  [../work/../midwest.csv, PID,area,poptotal...]
    //          [../work/../livestock.csv, value...]
    
    numeric_cols.map{my_tuple -> my_tuple[1].split(',').collect{my_column -> new Tuple(my_tuple[0], my_column)}}.flatten().view()
    // output:  ../work/../livestock.csv            (incorrect)
    //          value
    //          ../work/../midwest.csv
    //          PID

    numeric_cols.flatMap{my_tuple -> my_tuple[1].split(',').collect{my_column -> new Tuple(my_tuple[0], my_column)}}.view()
    // output:  [../work/../livestock.csv, value]   (correct)
    //          [../work/../midwest.csv, PID]
}
```

## Gather (many-to-one)
The main operators for combining the results of channels are the [toList](https://www.nextflow.io/docs/latest/operator.html#tolist) and [collect operators](https://www.nextflow.io/docs/latest/operator.html#tolist). It is easy to forget that we are not operating on actual lists, but asynchronous channels of lists. Gather operations essentially wait for some or all of the channel entries, but it is done automatically.

### Example 3. SPLIT_VIDEO

This combines ideas from previous examples, but since we have decided it only needs to work on a single video, we do away with tuples completely. The contents of each process do not matter but essentially, we split up a video into 2 second chunks, convert the colours of each chunk frame-by-frame, and finally recombine them (in order!) with the original audio.

Note COMBINE_VIDEO has two input channels. Do input channels need to be the same size? Usually yes, but in Nextflow, single-value channels just repeat their value forever. It is tempting to use multiple channels to track metadata instead of tuples in `Example 3` but this is almost never a good approach.

> [!TIP]
> Run using `nextflow run main.nf -with-docker "borda/docker_python-opencv-ffmpeg"` if you have docker but not ffmpeg/opencv installed. You can also define containers per-process, just like conda above.
> You can even add --input ./path/to/your.mp4 to run it on a different video!

```go
process CHUNK_VIDEO {
    input:
    path video

    output:
    path "chunk_*.mp4"

    script:
    """
    #!/usr/bin/env bash
    ffmpeg -i "$video" -c copy -map 0 -segment_time 00:00:02 -f segment chunk_%03d.mp4
    """
}

process CONVERT_CHUNK {
    cpus 1
    memory 500.MB

    input:
    path video

    output:
    path "*convert.avi"

    script:
    """
    #!/usr/bin/env python
    import cv2
    input = cv2.VideoCapture("$video")
    size = (int(input.get(cv2.CAP_PROP_FRAME_WIDTH)), int(input.get(cv2.CAP_PROP_FRAME_HEIGHT)))
    fps = input.get(cv2.CAP_PROP_FPS)
    output = cv2.VideoWriter("${video}_convert.avi", cv2.VideoWriter_fourcc(*"H264"), fps, size)
    while input.grab():
        _, img = input.retrieve()
        hls_img = cv2.cvtColor(img, cv2.COLOR_BGR2HLS)
        output.write(hls_img)
    input.release()
    output.release()
    """
}

process COMBINE_VIDEO {
    publishDir "results"

    input:
    path source
    path chunks

    output:
    path "output.mp4"

    script:
    """
    #!/usr/bin/env bash
    ffmpeg -i "concat:${chunks.join("|")}" -i "$source" -c:v copy -c:a copy -map 0:v:0 -map 1:a:0 output.mp4
    """
}

params.input = "https://packaged-media.redd.it/fodnczk22kzb1/pb/m2-res_480p.mp4?m=DASHPlaylist.mpd&v=1&e=1721041200&s=4cc9c875d6a7ae58c64759454725cbcb1d055a9e#t=0&name=video.mp4"

workflow {
    input_channel = Channel.of(params.input)
    chunk_channel = CHUNK_VIDEO(input_channel).flatten()
    convert_channel = CONVERT_CHUNK(chunk_channel).collect(sort: { unixpath -> unixpath.getName() })
    combine_channel = COMBINE_VIDEO(input_channel, convert_channel)
}
```

## Running on RNA2
Simply run `conda activate nf-env` and then use either conda or docker for workflow-specific dependencies. I have found that, while you can create an environment.yml and use it from Nextflow, some pip dependencies can take ages to install this way.

## Where to go from here?
Hopefully you will now have some intuition for when Nextflow might be a good fit for a project, and when it probably isn't. I've found it very concise to write mostly file-based workflows, and you get dependency features, HPC execution and cpu/memory limits for free. A lot of guides will have you believe "monolithic" scripts are always bad but they can be much faster for sequential scripts.

If you like learning by example, the [patterns](https://nextflow-io.github.io/patterns/) website is very helpful. Otherwise, view the [official documentation here](https://www.nextflow.io/docs/latest/). It's best to learn with particular scripts in mind since the documentation gives equal weighting to commonly-used and hardly-used features.

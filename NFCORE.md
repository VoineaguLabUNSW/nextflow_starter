# Part 2: nf-core Starter
## Running & Editing Community Workflows

Now that the basic syntax has been introduced, we can go over running Nextflow community workflows, such as nf-core/rnaseq, in practice. You can also configure many pipeline behaviours without modifying the process files themselves using special `.config` text files. Since errors can happen inside either a process or inside Nextflow, we will also go over some common error messages.

Something we will not discuss in my detail is project layout - in past examples, we placed multiple processes in the same file. **nf-core requires all community workflows to have a relatively consistent layout** that encourages common processes (e.g. fastqc) to be shared between projects.

> [!NOTE]
> What you should learn:
> - running basics
> - configuration scopes
> - nf-core/rnaseq basics
> - errors and resuming

## Running Basics
### Commands
In previous examples, we typically used `nextflow run my_pipeline.nf` to run a Nextflow file, but `nextflow run my_folder` or `nextflow run github/repo` also work if they contain "main.nf" at the root level. For instance to run [https://github.com/nf-core/rnaseq](https://github.com/nf-core/rnaseq) we can simply call `nextflow run nf-core/rnaseq`.

### Flags
Single '-' flags are for changing how Nextflow launches, double '--' flags are passed to the pipeline as parameters. For instance `nextflow run nf-core/rnaseq -bg` runs the pipeline [in the background](https://www.nextflow.io/docs/latest/cli.html#execution-as-a-background-job), while `nextflow run nf-core/rnaseq --genome hg38` sets the pipeline to use a specific iGenome. Hence `-bg` is available to all pipelines, but `--genome` is rnaseq-specific!

### Monitoring
In the same folder as you called the run command, you can check progress/previous runs using `nextflow log`, or even stop the current run using `Ctrl+C` (or if `-bg` was used, ``kill `cat .nextflow.pid` ``).

## Configuration Scopes
Based on the previous Nextflow syntax starter presentation, you may be able to guess that `nextflow run nf-core/rnaseq` uses whatever dependencies are already installed, and individual processes will error with e.g. `bash: star: command not found` if they are missing a dependency. Thankfully, **nf-core requires all community processes to define both `conda` and `container` fields** like below:

`main.nf`
```go
process WRITE_GREETINGS {
    container "python:3.12"
    conda "python=3.12::conda-forge"

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
```

Configuration in Nextflow is based around [scopes](https://www.nextflow.io/docs/latest/config.html#config-scopes). To opt-in to using pre-defined containers or conda, we can set the configuration scope `docker.enabled = true` or `conda.enabled = true` using, for example `nextflow run nf-core/rnaseq -c rna2.config` where `rna2.config` is a simple text file:

`rna2.config`
```go
docker.enabled = true
```

But there is another Nextflow feature that saves us from needing to define a separate .config for each machine - [profiles](https://www.nextflow.io/docs/latest/config.html#config-profiles). And conveniently, **nf-core requires all community processes to define `conda`, `docker`, `singularity` and `test` profiles** like below:

`example.config`
```go
profiles {
    docker { // already available in all nf-core workflows
        docker.enabled = true
    }
    singularity { // already available in all nf-core workflows
        singularity.enabled = true
    }
    my_custom_profile { // custom idea
        process.executor = "pbspro"
        singularity.enabled = true
    }
}
```

Putting all these pieces together, the command to run RNA-Seq on rna2 is quite simple. But hopefully you now understand when you can use built-in profiles, and when to just write your own:

```bash
nextflow run nf-core/rnaseq -profile docker
```

One thing I will mention but not demonstrate here is process-specific scopes. You can change **most** `process.x` settings using configuration alone, using `withName` process pattern matching.
For instance, you might want to adjust STAR flags specifically, or ensure Alphafold jobs go to a particular GPU queue on your cluster. This is used [extensively in nf-core](https://github.com/nf-core/rnaseq/blob/master/conf/modules.config), so you do have to be careful when overwriting individual settings.
It's also how [nf-optimizer](https://github.com/WalshKieran/nf-optimizer) defines memory/cpu limits for each type of process.

## nf-core/rnaseq Basics

If you have run this workflow using an interface, the minimum parameters are exactly the same: an `--input` samplesheet and EITHER a `--genome` iGenome name (e.g. hg38, GRCh37) OR both a `--gtf/--gff` annotation and `--fasta` genome fasta. 

The samplesheet format is best complained by the official example (see working example [here](https://raw.githubusercontent.com/nf-core/test-datasets/rnaseq/samplesheet/v3.10/samplesheet_test.csv)):
```
sample,fastq_1,fastq_2,strandedness
CONTROL_REP1,AEG588A1_S1_L002_R1_001.fastq.gz,AEG588A1_S1_L002_R2_001.fastq.gz,auto
CONTROL_REP1,AEG588A1_S1_L003_R1_001.fastq.gz,AEG588A1_S1_L003_R2_001.fastq.gz,auto
CONTROL_REP1,AEG588A1_S1_L004_R1_001.fastq.gz,AEG588A1_S1_L004_R2_001.fastq.gz,auto
```

So our command becomes something like this:
```bash
conda activate nf-env           `# On rna2, Nextflow is installed using conda`
nextflow run nf-core/rnaseq     `# Name of nf-core pipeline` \
    -latest                     `# Always pull latest even if cached locally` \
    -bg                         `# Run in background ` \
    -resume                     `# Always re-use anything in work directory` \
    -r 3.14.0                   `# Pinning specific version is good practice` \
    -profile docker             `# Running on rna2` \
    --input samplesheet.csv \
    --fasta 'https://ftp.ensembl.org/pub/release-112/fasta/homo_sapiens/dna/Homo_sapiens.GRCh38.dna_sm.primary_assembly.fa.gz' \
    --gtf 'https://ftp.ensembl.org/pub/release-112/gtf/homo_sapiens/Homo_sapiens.GRCh38.112.gtf.gz' \
    --outdir ./results > /dev/null 2>&1
```

You can read about other parameters [here](https://nf-co.re/rnaseq/parameters/). Some notable ones for a circular RNA lab might be [--remove_ribo_rna](https://nf-co.re/rnaseq/parameters#remove_ribo_rna).

> [!NOTE]
> The "\\" in the above examples continues the command as a single line.
> `` `# comment` `` is a neat way to put comments mid-line in bash.

## Errors and Resuming
- Long hanging -> generally a GitHub throttle issue due to UNSW ip (wait or use GitHub credentials).
- Singularity failed to pull -> generally a quay.io throttle issue.
- Failed to write file / IO error -> out of space.
- Docker daemon not started -> launch docker on e.g. your laptop before running Nextflow.

## Where to go from here?
On RNA2, using the docker profile should be sufficient after activating `nf-env`. On Katana you could use the singularity profile to run all tasks in a single compute job, but would need to create a custom config that specifies `process.executor = "pbspro"` to allow each task in a separate Katana job. Checkout my [katana-rnaseq-start](https://github.com/WalshKieran/katana-rnaseq-start) GitHub page to use a pre-written config for Katana.
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
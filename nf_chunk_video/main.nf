process CHUNK_VIDEO {
    container "borda/docker_python-opencv-ffmpeg"

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
    container "borda/docker_python-opencv-ffmpeg"

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
    container "borda/docker_python-opencv-ffmpeg"
    
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
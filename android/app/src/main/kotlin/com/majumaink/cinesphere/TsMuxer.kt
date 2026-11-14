package com.majumaink.cinesphere

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

/**
 * Remuxes the concatenated MPEG-TS segments of an HLS download into a single
 * MP4 without re-encoding. Video and audio may come from separate renditions.
 */
object TsMuxer {
    private const val BUFFER_SIZE = 16 * 1024 * 1024

    fun mux(videoPath: String, audioPath: String?, outputPath: String): Boolean {
        val extractors = mutableListOf<MediaExtractor>()
        var muxer: MediaMuxer? = null
        var success = false
        try {
            val out = File(outputPath)
            out.parentFile?.mkdirs()
            if (out.exists()) out.delete()

            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            val video = openTrack(videoPath, "video/", extractors)
                ?: return false
            val videoOut = muxer.addTrack(video.second)

            // A container that rejects the audio codec (e.g. AC-3) still yields
            // a usable silent picture rather than a failed download.
            var audio: Pair<MediaExtractor, MediaFormat>? = null
            var audioOut = -1
            if (audioPath != null) {
                val candidate = openTrack(audioPath, "audio/", extractors)
                if (candidate != null) {
                    try {
                        audioOut = muxer.addTrack(candidate.second)
                        audio = candidate
                    } catch (_: Exception) {
                        candidate.first.release()
                        extractors.remove(candidate.first)
                    }
                }
            }

            muxer.start()
            val buffer = ByteBuffer.allocateDirect(BUFFER_SIZE)
            val info = MediaCodec.BufferInfo()

            var written = writeTrack(video.first, videoOut, buffer, info, muxer)
            if (audio != null) {
                written += writeTrack(audio.first, audioOut, buffer, info, muxer)
            }

            muxer.stop()
            // A media extractor can open a container yet yield no samples; the
            // muxer then emits a header-only file that plays as 0:00.
            success = written > 0 && out.length() > 0
            return success
        } catch (_: Exception) {
            return false
        } finally {
            try {
                muxer?.release()
            } catch (_: Exception) {
            }
            extractors.forEach {
                try {
                    it.release()
                } catch (_: Exception) {
                }
            }
            if (!success) {
                // MediaMuxer creates the file eagerly, so a failed remux would
                // otherwise leave an empty .mp4 next to the staged playlist.
                try {
                    File(outputPath).delete()
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun openTrack(
        path: String,
        mimePrefix: String,
        extractors: MutableList<MediaExtractor>
    ): Pair<MediaExtractor, MediaFormat>? {
        if (!File(path).exists()) return null
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith(mimePrefix)) {
                    extractor.selectTrack(i)
                    extractors.add(extractor)
                    return extractor to format
                }
            }
        } catch (_: Exception) {
        }
        extractor.release()
        return null
    }

    private fun writeTrack(
        extractor: MediaExtractor,
        outTrack: Int,
        buffer: ByteBuffer,
        info: MediaCodec.BufferInfo,
        muxer: MediaMuxer
    ): Int {
        var samples = 0
        while (true) {
            val size = extractor.readSampleData(buffer, 0)
            if (size < 0) break
            info.offset = 0
            info.size = size
            info.presentationTimeUs = extractor.sampleTime
            // Only the sync bit maps onto MediaCodec's flag space; the other
            // MediaExtractor bits mean something else to the muxer.
            info.flags = if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
                MediaCodec.BUFFER_FLAG_KEY_FRAME
            } else {
                0
            }
            muxer.writeSampleData(outTrack, buffer, info)
            samples++
            extractor.advance()
        }
        return samples
    }
}

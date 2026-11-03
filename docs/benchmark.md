# Benchmark: AWDL allowed vs held down

A quick, real-world measurement of what AWDL does to Wi-Fi latency, made with
[`scripts/latency-bench.sh`](../scripts/latency-bench.sh).

## Setup

| | |
|---|---|
| Mac | MacBook Air (M2), macOS 27.2 |
| Wi-Fi | 802.11ax, 5 GHz channel 40, 20 MHz, office access point |
| Target | default gateway (one hop) |
| Method | ping every 100 ms, 60 s per phase (600 packets), phases alternated twice |
| Switching | `awdl-guardctl mode allow` / `awdl-guardctl mode block`, nothing else changed |

The Mac was in normal use (no call running) during all four phases.

## Results

| | AWDL allowed (1) | AWDL held down (1) | AWDL allowed (2) | AWDL held down (2) |
|---|---:|---:|---:|---:|
| Median | 3.6 ms | 2.8 ms | 4.5 ms | 2.9 ms |
| Average | 26.9 ms | 3.2 ms | 19.3 ms | 3.3 ms |
| p95 | 81.8 ms | 5.7 ms | 77.6 ms | 5.3 ms |
| p99 | 643.9 ms | 9.9 ms | 90.8 ms | 10.4 ms |
| Max | 957.4 ms | 23.0 ms | 228.2 ms | 25.2 ms |
| Jitter | 20.4 ms | 0.9 ms | 29.5 ms | 1.0 ms |
| Replies over 30 ms | 84 | **0** | 143 | **0** |
| Packet loss | 0.7 % | 0 % | 0 % | 0 % |

## What it means

- **Typical latency barely changes.** Most packets are fast either way; the median moves by
  about 1 ms.
- **The tail is where AWDL hurts.** With AWDL allowed, 1 packet in 20 took more than 75 ms
  and some approached a second. These stalls line up with the radio leaving the access
  point's channel to listen on the AWDL channels.
- **Held down, the spikes disappear.** Zero replies over 30 ms in both runs, p95 down by
  about 14x and jitter down by 20-30x.

Real-time traffic (voice, video, screen sharing, games) is sensitive to exactly these
spikes and to jitter, not to the median. That is why calls sound choppy on an otherwise
fast network.

## Caveats

This is one Mac, one access point and four minutes. Results depend on the access point's
channel, nearby Apple devices and what is using AWDL at the time. Run the script on your
own network before and after:

```bash
./scripts/latency-bench.sh 60     # AWDL allowed
awdl-guardctl mode block
./scripts/latency-bench.sh 60     # AWDL held down
awdl-guardctl mode default
```

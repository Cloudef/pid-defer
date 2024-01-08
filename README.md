# pid-defer

Run processes that will be cleaned up when other process exits. (Linux only)

---

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Project is tested on zig version 0.12.0-dev.2058+04ac028a2

## How to use

Common problem with shell scripts is wanting to have background processes that needs to be cleaned up when some arbitary main process exits.
This project tries to solve that problem, acting as sort of local service / process handler.

```bash
defer ppid my-command [args]
```

> [!WARNING]
> It's possible for a race condition to occur if `ppid` dies and is replaced by other process with same `pid` before `defer` calls `pidfd_open`.

### Example

```bash
defer $$ watch -t -x echo "this is gonna go away in 5 seconds (hopefully)"
sleep 5
# defer and watch -t -x should exit now
```

### Handling double forking processes

When child double forks itself or spawns other children that might double fork, you can use the `reaper` binary to handle those.

```bash
defer $$ reaper daemonize -o /dev/stdout "$(which watch)" -t -x echo "this is gonna go away in 5 seconds (hopefully)"
sleep 5
# defer, reaper and watch -t -x should exit now
```

## waitpid

This repo also offers extra tool called `waitpid`. It does exactly what the name says.

```bash
echo "sleeping for 5 secs now"
sleep 5 &
waitpid $!
echo "okay did we wait for the sleep properly?"
```

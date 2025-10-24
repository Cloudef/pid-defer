{
  description = "pid-defer flake";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    zig2nix.url = "github:Cloudef/zig2nix";
  };

  outputs = { flake-utils, zig2nix, ... }:
  (flake-utils.lib.eachDefaultSystem (system: let
      env = zig2nix.outputs.zig-env.${system} {
        zig = zig2nix.outputs.packages.${system}.zig-0_12_0;
      };
    in with builtins; with env.lib; with env.pkgs.lib; {
      # package
      packages.default = env.package {
        pname = "pid-defer";
        version = "1.0.0";
        src = cleanSource ./.;
      };

      # nix run .#defer
      apps.defer = env.app [] "zig build run-defer -- \"$@\"";

      # nix run .#reaper
      apps.reaper = env.app [] "zig build run-reaper -- \"$@\"";

      # nix run .#waitpid
      apps.waitpid = env.app [] "zig build run-waitpid -- \"$@\"";

      # nix run .#test-defer
      apps.test-defer = env.app [] ''
        zig build
        ./zig-out/bin/defer $$ watch -t -x echo "this is gonna go away in 5 seconds (hopefully)"
        sleep 5
      '';

      # nix run .#test-reaper
      apps.test-reaper = env.app [env.pkgs.daemonize] ''
        zig build
        ./zig-out/bin/defer $$ ./zig-out/bin/reaper daemonize -o /dev/stdout "$(which watch)" -t -x echo "this is gonna go away in 5 seconds (hopefully)"
        sleep 5
      '';

      # nix run .#test-waitpid
      apps.test-waitpid = env.app [] ''
        zig build
        echo "sleeping for 5 secs now"
        sleep 5 &
        ./zig-out/bin/waitpid $!
        echo "okay did we wait for the sleep properly?"
      '';

      # nix run .#version
      apps.version = env.app [] "zig version";

      # nix run .#readme
      apps.readme = let
        project = "pid-defer";
      in env.app [] (replaceStrings ["`"] ["\\`"] ''
      cat <<EOF
      # ${project}

      Run processes that will be cleaned up when other process exits. (Linux only)

      ---

      [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

      Project is tested on zig version $(zig version)

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
      defer \$\$ watch -t -x echo "this is gonna go away in 5 seconds (hopefully)"
      sleep 5
      # defer and watch -t -x should exit now
      ```

      ### Handling double forking processes

      When child double forks itself or spawns other children that might double fork, you can use the `reaper` binary to handle those.

      ```bash
      defer \$\$ reaper daemonize -o /dev/stdout "\$(which watch)" -t -x echo "this is gonna go away in 5 seconds (hopefully)"
      sleep 5
      # defer, reaper and watch -t -x should exit now
      ```

      ## waitpid

      This repo also offers extra tool called `waitpid`. It does exactly what the name says.

      ```bash
      echo "sleeping for 5 secs now"
      sleep 5 &
      waitpid \$!
      echo "okay did we wait for the sleep properly?"
      ```
      EOF
      '');

      # nix develop
      devShells.default = env.mkShell {};
    }));
}

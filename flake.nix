{
  description = "zig-fsm-compiler flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    zig-stdenv.url = "github:Cloudef/nix-zig-stdenv";
  };

  outputs = { flake-utils, nixpkgs, zig-stdenv, ... }:
  (flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.outputs.legacyPackages."${system}";
      zig = zig-stdenv.versions.${system}.master;
      app = deps: script: {
        type = "app";
        program = toString (pkgs.writeShellApplication {
          name = "app";
          runtimeInputs = [ zig ] ++ deps;
          text = ''
            # shellcheck disable=SC2059
            error() { printf -- "error: $1" "''${@:1}" 1>&2; exit 1; }
            [[ -f ./flake.nix ]] || error 'Run this from the project root'
            export ZIG_BTRFS_WORKAROUND=1
            ${script}
            '';
        }) + "/bin/app";
      };

      local-daemon = pkgs.stdenvNoCC.mkDerivation {
        name = "local-daemon";
        version = "1.0.0";
        src = ./.;
        nativeBuildInputs = [ pkgs.zig.hook ];
      };
    in {
      # package
      packages.default = local-daemon;

      # nix run .#local-daemon
      apps.local-daemon = app [] "zig build run-local-daemon -- \"$@\"";

      # nix run .#waitpid
      apps.waitpid = app [] "zig build run-waitpid -- \"$@\"";

      # nix run .#test-local-daemon
      apps.test-local-daemon = app [] ''
        zig build
        ./zig-out/bin/local-daemon $$ watch -t -x echo "this is gonna go away in 5 seconds (hopefully)"
        sleep 5
      '';

      # nix run .#test-waitpid
      apps.test-waitpid = app [] ''
        zig build
        echo "sleeping for 5 secs now"
        sleep 5 &
        ./zig-out/bin/waitpid $!
        echo "okay did we wait for the sleep properly?"
      '';

      # nix run .#version
      apps.version = app [] "zig version";

      # nix run .#readme
      apps.readme = let
        project = "local-daemon";
      in with pkgs; app [graphviz] (builtins.replaceStrings ["`"] ["\\`"] ''
      cat <<EOF
      # ${project}

      Run processes that will be cleaned up when parent exits. (Linux only)

      ---

      [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

      Project is tested on zig version $(zig version)

      ## How to use

      Common problem with shell scripts is wanting to have background processes that needs to be cleaned up when some arbitary main process exits.
      This project tries to solve that problem, acting as sort of local service / process handler.

      ```bash
      ${project} ppid my-command [args]
      ```

      > [!WARNING]
      > It's possible for a race condition to occur if `ppid` dies and is replaced by other process with same `pid` before ${project} calls `pidfd_open`.

      ### Example

      ```bash
      ${project} \$\$ watch -t -x echo "this is gonna go away in 5 seconds (hopefully)"
      sleep 5
      # ${project} and watch -t -x should exit now
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
      devShells.default = pkgs.mkShell {
        buildInputs = [ zig ];
        shellHook = "export ZIG_BTRFS_WORKAROUND=1";
      };
    }));
}

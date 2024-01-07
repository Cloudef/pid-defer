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

      # nix run
      apps.default = app [] "zig build run -- \"$@\"";

      # nix run .#test
      apps.test = app [] ''
        zig build
        ./zig-out/bin/local-daemon $$ watch -t -x echo "this is gonna go away in 5 seconds (hopefully)"
        sleep 5
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
      EOF
      '');

      # nix develop
      devShells.default = pkgs.mkShell {
        buildInputs = [ zig ];
        shellHook = "export ZIG_BTRFS_WORKAROUND=1";
      };
    }));
}

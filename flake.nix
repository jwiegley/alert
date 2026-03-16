{
  description = "Alert - Growl-style notification system for Emacs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        emacs = pkgs.emacs-nox;

        # Runtime dependencies only
        emacsWithDeps = (pkgs.emacsPackagesFor emacs).emacsWithPackages (epkgs: [
          epkgs.gntp
          epkgs.log4e
        ]);

        # Runtime + CI/lint dependencies
        emacsForCI = (pkgs.emacsPackagesFor emacs).emacsWithPackages (epkgs: [
          epkgs.gntp
          epkgs.log4e
          epkgs.package-lint
          epkgs.relint
        ]);

        src = pkgs.lib.cleanSource self;

      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "emacs-alert";
          version = "1.2";
          inherit src;
          nativeBuildInputs = [ emacsWithDeps ];
          buildPhase = ''
            emacs -Q --batch \
              -f batch-byte-compile \
              alert.el
          '';
          installPhase = ''
            mkdir -p $out/share/emacs/site-lisp
            cp alert.el alert.elc $out/share/emacs/site-lisp/
          '';
        };

        checks = {
          # Ensure the package builds successfully
          build = self.packages.${system}.default;

          # Byte-compile with all warnings treated as errors
          byte-compile = pkgs.runCommand "check-byte-compile" {
            nativeBuildInputs = [ emacsWithDeps ];
          } ''
            cp ${src}/alert.el .
            emacs -Q --batch \
              --eval '(setq byte-compile-error-on-warn t)' \
              -f batch-byte-compile \
              alert.el
            touch $out
          '';

          # Run ERT test suite
          test = pkgs.runCommand "check-test" {
            nativeBuildInputs = [ emacsWithDeps ];
          } ''
            cp ${src}/alert.el ${src}/alert-test.el .
            emacs -Q --batch \
              -L . \
              -l alert-test \
              -f ert-run-tests-batch-and-exit
            touch $out
          '';

          # Check regexp patterns for correctness
          relint = pkgs.runCommand "check-relint" {
            nativeBuildInputs = [ emacsForCI ];
          } ''
            cp ${src}/alert.el .
            emacs -Q --batch \
              -l relint \
              --eval '(setq relint-batch-highlight nil)' \
              -f relint-batch \
              alert.el
            touch $out
          '';

          # NOTE: indent check is available via: nix run .#format -- alert.el
          # It is excluded from blocking checks because alert.el has
          # legacy indentation that would require a large reformatting diff.
          #
          # NOTE: The following checks are not applicable to Emacs Lisp:
          #
          # - Code coverage: ERT lacks practical coverage tooling
          # - Performance profiling: not meaningful as a build gate for a library
          # - Fuzz testing: not practical for Emacs Lisp
          # - Memory sanitizer: Emacs uses garbage collection
          #
          # package-lint is excluded from nix checks because it requires
          # network access to verify package archives.  Run it locally via:
          #   emacs -Q --batch -l package-lint -f package-lint-batch-and-exit alert.el
        };

        # Format all Elisp files to canonical Emacs indentation
        apps.format = flake-utils.lib.mkApp {
          drv = pkgs.writeShellScriptBin "alert-format" ''
            files="''${@:-alert.el}"
            for f in $files; do
              ${emacsWithDeps}/bin/emacs -Q --batch \
                "$f" \
                --eval '(progn (emacs-lisp-mode) (indent-region (point-min) (point-max)))' \
                -f save-buffer
              echo "Formatted: $f"
            done
          '';
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            emacsForCI
            pkgs.lefthook
          ];
          shellHook = ''
            lefthook install 2>/dev/null || true
          '';
        };
      }
    );
}

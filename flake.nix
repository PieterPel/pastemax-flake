{
  description = "A Nix flake for pastemax - A modern file viewer application for developers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    pastemax-src = {
      url = "github:kleneway/pastemax";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, pastemax-src }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (system: 
        let
          pkgs = nixpkgs.legacyPackages.${system};

          pastemax = pkgs.buildNpmPackage rec {
            pname = "pastemax";
            version = "1.1.0";

            src = pastemax-src;

            # Hash of the node_modules dependencies
            # Run `nix build` once to get the correct hash, then update this
            npmDepsHash = "sha256-422mnu59LwOSvLqGeardz1NnGNjCvIJ6IjRUACq+K2s=";

            # Use Node.js 20 to match the upstream project
            nodejs = pkgs.nodejs_20;

            # Prevent electron from downloading during build
            ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
            ELECTRON_OVERRIDE_DIST_PATH = "${pkgs.electron}/libexec/electron";

            # Native build inputs needed for the build process
            nativeBuildInputs = with pkgs; [
              python3
            ];

            # Build inputs needed at runtime
            buildInputs = with pkgs; [
              electron
            ];

            # Don't run npm install since buildNpmPackage handles it
            dontNpmInstall = false;

            # Configure npm to use system electron
            npmFlags = [ "--ignore-scripts" ];

            # Build the Vite frontend
            buildPhase = ''
              runHook preBuild
              
              echo "Building Vite frontend..."
              npm run build
              
              runHook postBuild
            '';

            # Install the application
            installPhase = ''
              runHook preInstall
              
              mkdir -p $out/lib/pastemax
              mkdir -p $out/bin
              
              # Copy electron main process files first
              cp -r electron $out/lib/pastemax/
              
              # Copy the built frontend to where electron expects it
              cp -r dist $out/lib/pastemax/electron/
              
              # Copy package.json for electron
              cp package.json $out/lib/pastemax/
              
              # Copy node_modules (needed for electron runtime)
              cp -r node_modules $out/lib/pastemax/
              
              # Create wrapper script
              cat > $out/bin/pastemax << EOF
#!/bin/sh
exec ${pkgs.electron}/bin/electron $out/lib/pastemax "\$@"
EOF
              
              chmod +x $out/bin/pastemax
              
              runHook postInstall
            '';

            # Desktop entry for Linux
            postInstall = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
              mkdir -p $out/share/applications
              cat > $out/share/applications/pastemax.desktop << 'EOF'
[Desktop Entry]
Name=PasteMax
Comment=A modern file viewer application for developers
Exec=$out/bin/pastemax
Icon=pastemax
Type=Application
Categories=Development;Utility;
Keywords=clipboard;code;developer-tools;file-viewer;
EOF

              mkdir -p $out/share/pixmaps
              # Use a simple icon if available, or create a placeholder
              if [ -f public/favicon.png ]; then
                cp public/favicon.png $out/share/pixmaps/pastemax.png
              fi
            '';

            meta = with pkgs.lib; {
              description = "A modern file viewer application for developers to easily navigate, search, and copy code from repositories";
              homepage = "https://kleneway.github.io/pastemax";
              license = licenses.mit;
              maintainers = [ ];
              platforms = platforms.unix;
              mainProgram = "pastemax";
            };
          };
        in
        {
          default = pastemax;
          pastemax = pastemax;
        }
      );

      devShells = forAllSystems (system: 
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in 
        {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              nodejs_20
              electron
              python3
            ];

            shellHook = ''
              echo "PasteMax development environment"
              echo "Available commands:"
              echo "  npm run dev - Start development server"
              echo "  npm run build - Build for production"
              echo "  npm run dev:electron - Start electron in dev mode"
              echo "  npm run package - Package electron app"
            '';
          };
        }
      );

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.pastemax}/bin/pastemax";
        };
        pastemax = {
          type = "app";
          program = "${self.packages.${system}.pastemax}/bin/pastemax";
        };
      });
    };
}
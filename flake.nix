{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    colmena.url = "github:zhaofengli/colmena";
  };

  outputs = { self, nixpkgs, colmena, ... }: {

    lib = {
      mkProxy = addr: {
        proxyPass = addr;
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };

    nixosModules = {
      nginx = { config, pkgs, lib, ... }: {
        security.acme = {
          acceptTerms = true;
          defaults.email = "sahiti93@gmail.com";
        };
        services.nginx = {
          enable = true;
          package = pkgs.openresty;
          virtualHosts.${config.networking.fqdn} = {
            forceSSL = true;
            enableACME = true;
            locations = {
              "/" =
                let catflixRoot = pkgs.writeTextDir "www/index.html" ./index.html;
                in {
                  root = "${catflixRoot}/www";
                  index = "index.html";
                };
              "/cats/" = self.lib.mkProxy "http://localhost:9000/cats/";
            };
          };
        };
        services.prometheus.exporters.nginx.enable = true;
        services.prometheus.scrapeConfigs = [{
          job_name = "nginx";
          static_configs = [{
            targets = [
              "${config.networking.fqdn}:${
                builtins.toString
                config.services.prometheus.exporters.nginx.port
              }"
            ];
          }];
        }];

      };

      minio = { config, pkgs, lib, ... }: {
        services.minio = {
          enable = true;
          browser = true;
        };
        services.prometheus.scrapeConfigs = [{
          job_name = "minio";
          bearer_token = "TOKEN";
          metrics_path = "/minio/v2/metrics/cluster";
          scheme = "https";
          static_configs = [{ targets = [ config.networking.fqdn ]; }];
        }];
      };
      monitoring = { config, pkgs, lib, ... }: {
        services.prometheus.enable = true;
        services.grafana = {
          enable = true;
          settings = {
            server = {
              http_addr = "127.0.0.1";
              # and Port
              http_port = 3000;
              domain = config.networking.fqdn;
              root_url =
                "https://${config.networking.fqdn}/grafana/"; # Not needed if it is `https://your.domain/`
              serve_from_sub_path = true;
            };
          };
          provision = {
            enable = true;
            datasources.settings = {
              apiVersion = 1;
              datasources = [{
                name = "prometheus";
                type = "prometheus";
                url = "http://localhost:${
                    builtins.toString config.services.prometheus.port
                  }";
              }];
            };
          };
        };
        services.nginx.virtualHosts."${config.networking.fqdn}" = {
          locations."/grafana/" = self.lib.mkProxy "http://${
              toString config.services.grafana.settings.server.http_addr
            }:${toString config.services.grafana.settings.server.http_port}";
        };
      };
    };

    colmenaHive = colmena.lib.makeHive {
      meta = {
        nixpkgs = import nixpkgs {
          system = "x86_64-linux";
          overlays = [ ];
        };
      };

      catpix = { name, nodes, ... }: {
        deployment = { targetHost = "34.29.30.70"; };
        networking.fqdn = "catpix.itihas.xyz";
        imports = with self.nixosModules; [
          "${nixpkgs}/nixos/modules/virtualisation/google-compute-image.nix"
          nginx
          minio
          monitoring
        ];
      };
    };
  };
}

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
      mkProvider = name: path: {
        inherit name;
        orgId = 1;
        folder = "";
        type = "file";
        disableDeletion = true;
        updateIntervalSeconds = 10;
        options.path = path;
      };
    };

    nixosModules = {
      catpix-nginx = { config, pkgs, lib, ... }: {
        security.acme = {
          acceptTerms = true;
          defaults.email = "sahiti93@gmail.com";
        };
        services.nginx = {
          enable = true;
          package = pkgs.openresty;
          statusPage = true;
          virtualHosts.${config.networking.fqdn} = {
            forceSSL = true;
            enableACME = true;
            locations = {
              "/" = let
                catpixRoot = pkgs.writeTextDir "/index.html"
                  (builtins.readFile ./index.html);
              in {
                root = catpixRoot;
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
              "localhost:${
                toString
                config.services.prometheus.exporters.nginx.port
              }"
            ];
          }];
        }];
        services.grafana.provision.dashboards.settings.providers =
          [ (self.lib.mkProvider "nginx" ./dashboards/nginx.json) ];
      };

      catpix-minio = { config, pkgs, lib, ... }: {
        services.minio = {
          enable = true;
          browser = true;
        };
        systemd.services.minio.environment.MINIO_PROMETHEUS_AUTH_TYPE =
          "public";
        services.prometheus.scrapeConfigs = [{
          job_name = "minio";
          metrics_path = "/minio/v2/metrics/cluster";
          static_configs = [{ targets = [ "localhost:9000" ]; }];
        }];
        services.grafana.provision.dashboards.settings.providers =
          [ (self.lib.mkProvider "minio" ./dashboards/minio.json) ];

      };
      catpix-monitoring = { config, pkgs, lib, ... }: {
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
                    toString config.services.prometheus.port
                  }";
              }];
            };
          };
        };
        services.nginx.virtualHosts."${config.networking.fqdn}" = {
          locations = {
            "/grafana/" = self.lib.mkProxy "http://localhost:${toString config.services.grafana.settings.server.http_port}";
            "/prometheus/" = self.lib.mkProxy "http://localhost:${toString config.services.prometheus.port}";
          };
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
        services.prometheus.exporters.node.enable = true;
        imports = with self.nixosModules; [
          "${nixpkgs}/nixos/modules/virtualisation/google-compute-image.nix"
          catpix-nginx
          catpix-minio
          catpix-monitoring
        ];
      };
    };
  };
}

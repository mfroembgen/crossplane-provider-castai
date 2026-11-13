package gkecluster

import (
	"github.com/crossplane/upjet/pkg/config"
)

// Configure configures individual resources by adding custom ResourceConfigurators.
func Configure(p *config.Provider) {
	p.AddResourceConfigurator("castai_gke_cluster", func(r *config.Resource) {
		r.ShortGroup = ""
		r.Kind = "GkeCluster"
		// Observed impersonation emails must not change the configured
		// authentication mode or conflict with credentials_json.
		r.LateInitializer = config.LateInitializer{
			IgnoredFields: []string{"target_service_account_email", "castai_service_account_email"},
		}

		r.Sensitive.AdditionalConnectionDetailsFn = func(attr map[string]any) (map[string][]byte, error) {
			conn := map[string][]byte{}
			if a, ok := attr["id"].(string); ok {
				conn["attribute.cluster_id"] = []byte(a)
			}
			return conn, nil
		}
	})
}

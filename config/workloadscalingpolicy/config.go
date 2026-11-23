package workloadscalingpolicy

import (
	"github.com/crossplane/upjet/pkg/config"
)

// Configure configures individual resources by adding custom ResourceConfigurators.
func Configure(p *config.Provider) {
	p.AddResourceConfigurator("castai_workload_scaling_policy", func(r *config.Resource) {
		r.ShortGroup = ""
		r.Kind = "ScalingPolicy"

		// An omitted scale-down window means 300 s, so late initialization
		// must keep an observed 0 instead of dropping it as empty.
		window := config.GetSchema(r.TerraformResource, "hpa_settings.native_hpa_spec.behavior.scale_down.stabilization_window_seconds")
		window.Description += "\n+upjet:crd:field:JSONTag=stabilizationWindowSeconds,omitzero\n+optional"
	})
}

/*
 * Create Logentries log
 */
resource "logentries_log" "log" {
  logset_id = "${var.logentries_set_id}"
  name      = "${var.app_name}"
  source    = "token"
}

/*
 * Create target group for ALB
 */
resource "aws_alb_target_group" "pwmanager" {
  name                 = "${replace("tg-${var.idp_name}-${var.app_name}-${var.app_env}", "/(.{0,32})(.*)/", "$1")}"
  port                 = "80"
  protocol             = "HTTP"
  vpc_id               = "${var.vpc_id}"
  deregistration_delay = "30"

  stickiness {
    type = "lb_cookie"
  }

  health_check {
    path    = "/site/system-status"
    matcher = "200"
  }
}

/*
 * Create listener rule for hostname routing to new target group
 */
resource "aws_alb_listener_rule" "pwmanager" {
  listener_arn = "${var.alb_https_listener_arn}"
  priority     = "50"

  action {
    type             = "forward"
    target_group_arn = "${aws_alb_target_group.pwmanager.arn}"
  }

  condition {
    field  = "host-header"
    values = ["${var.api_subdomain}.${var.cloudflare_domain}"]
  }
}

/*
 * Generate access token for UI to use to call API
 */
resource "random_id" "access_token_hash" {
  byte_length = 16
}

/*
 * Create ECS service for API
 */
data "template_file" "task_def" {
  template = "${file("${path.module}/task-definition-api.json")}"

  vars {
    access_token_hash                   = "${random_id.access_token_hash.hex}"
    alerts_email                        = "${var.alerts_email}"
    app_env                             = "${var.app_env}"
    auth_saml_checkResponseSigning      = "${var.auth_saml_checkResponseSigning}"
    auth_saml_entityId                  = "${var.auth_saml_entityId}"
    auth_saml_idpCertificate            = "${var.auth_saml_idpCertificate}"
    auth_saml_requireEncryptedAssertion = "${var.auth_saml_requireEncryptedAssertion}"
    auth_saml_signRequest               = "${var.auth_saml_signRequest}"
    auth_saml_sloUrl                    = "${var.auth_saml_sloUrl}"
    auth_saml_spCertificate             = "${var.auth_saml_spCertificate}"
    auth_saml_spPrivateKey              = "${var.auth_saml_spPrivateKey}"
    auth_saml_ssoUrl                    = "${var.auth_saml_ssoUrl}"
    cmd                                 = "/data/run.sh"
    code_length                         = "${var.code_length}"
    cpu                                 = "${var.cpu}"
    db_name                             = "${var.db_name}"
    docker_image                        = "${var.docker_image}"
    email_service_accessToken           = "${var.email_service_accessToken}"
    email_service_assertValidIp         = "${var.email_service_assertValidIp}"
    email_service_baseUrl               = "${var.email_service_baseUrl}"
    email_service_validIpRanges         = "${join(",", var.email_service_validIpRanges)}"
    email_signature                     = "${var.email_signature}"
    help_center_url                     = "${var.help_center_url}"
    id_broker_access_token              = "${var.id_broker_access_token}"
    id_broker_assertValidBrokerIp       = "${var.id_broker_assertValidBrokerIp}"
    id_broker_base_uri                  = "${var.id_broker_base_uri}"
    id_broker_validIpRanges             = "${join(",", var.id_broker_validIpRanges)}"
    idp_display_name                    = "${var.idp_display_name}"
    idp_name                            = "${var.idp_name}"
    logentries_key                      = "${logentries_log.log.token}"
    memory                              = "${var.memory}"
    mysql_host                          = "${var.mysql_host}"
    mysql_password                      = "${var.mysql_pass}"
    mysql_user                          = "${var.mysql_user}"
    password_rule_enablehibp            = "${var.password_rule_enablehibp}"
    password_rule_maxlength             = "${var.password_rule_maxlength}"
    password_rule_minlength             = "${var.password_rule_minlength}"
    password_rule_minscore              = "${var.password_rule_minscore}"
    recaptcha_secret_key                = "${var.recaptcha_secret}"
    recaptcha_site_key                  = "${var.recaptcha_key}"
    support_email                       = "${var.support_email}"
    support_feedback                    = "${var.support_feedback}"
    support_phone                       = "${var.support_phone}"
    support_url                         = "${var.support_url}"
    ui_cors_origin                      = "https://${var.ui_subdomain}.${var.cloudflare_domain}"
    ui_url                              = "https://${var.ui_subdomain}.${var.cloudflare_domain}/#"
  }
}

module "ecsservice" {
  source             = "github.com/silinternational/terraform-modules//aws/ecs/service-only?ref=2.5.0"
  cluster_id         = "${var.ecs_cluster_id}"
  service_name       = "${var.idp_name}-${var.app_name}"
  service_env        = "${var.app_env}"
  container_def_json = "${data.template_file.task_def.rendered}"
  desired_count      = "${var.desired_count}"
  tg_arn             = "${aws_alb_target_group.pwmanager.arn}"
  lb_container_name  = "web"
  lb_container_port  = "80"
  ecsServiceRole_arn = "${var.ecsServiceRole_arn}"
}

/*
 * Create Cloudflare DNS record
 */
resource "cloudflare_record" "apidns" {
  domain  = "${var.cloudflare_domain}"
  name    = "${var.api_subdomain}"
  value   = "${var.alb_dns_name}"
  type    = "CNAME"
  proxied = true
}

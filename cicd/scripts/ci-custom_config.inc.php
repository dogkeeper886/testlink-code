<?php
// CI custom configuration for TestLink
// Enables API and disables email

$tlCfg->api->enabled = TRUE;

// Disable email in CI
$g_smtp_host = '';
$tlCfg->smtp_host = '';

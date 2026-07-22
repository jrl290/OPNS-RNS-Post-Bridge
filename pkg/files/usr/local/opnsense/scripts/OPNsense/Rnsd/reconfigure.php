#!/usr/local/bin/php
<?php
/**
 * reconfigure.php — Generate Reticulum config from OPNSense config.xml
 *
 * Called by:
 *   1. +POST_INSTALL on package install
 *   2. configd action "reconfigure" on save in web UI
 *   3. service rnsd restart
 *
 * Reads OPNSense config.xml, renders the rnsd.conf template,
 * writes /usr/local/etc/reticulum/config, and restarts rnsd.
 */

// OPNSense bootstrap
require_once '/usr/local/etc/inc/config.inc';
require_once '/usr/local/etc/inc/util.inc';
require_once '/usr/local/etc/inc/config.inc';
require_once '/usr/local/etc/inc/auth.inc';

use OPNsense\Core\Config;

function main(): void
{
    $config = Config::getInstance()->object();
    $rnsdConfig = $config->OPNsense->Rnsd->general ?? null;

    $templatePath = '/usr/local/opnsense/service/templates/OPNsense/Rnsd/rnsd.conf';
    $outputPath   = '/usr/local/etc/reticulum/config';

    if (!file_exists($templatePath)) {
        fprintf(STDERR, "ERROR: Template not found at %s\n", $templatePath);
        exit(1);
    }

    // Build template variables
    $vars = [];
    if ($rnsdConfig !== null) {
        foreach ($rnsdConfig as $key => $value) {
            $vars[$key] = (string) $value;
        }
    }

    // Simple template rendering (Jinja-like, no full engine needed)
    $template = file_get_contents($templatePath);
    $rendered = renderTemplate($template, $vars);

    // Write config
    $dir = dirname($outputPath);
    if (!is_dir($dir)) {
        mkdir($dir, 0755, true);
    }

    file_put_contents($outputPath, $rendered);
    chmod($outputPath, 0644);

    fprintf(STDERR, "[reconfigure] Wrote %s (%d bytes)\n", $outputPath, strlen($rendered));

    // Restart rnsd if it's running
    $enabled = ($vars['enabled'] ?? '0') === '1';
    if ($enabled) {
        fprintf(STDERR, "[reconfigure] Restarting rnsd...\n");
        exec('/usr/local/etc/rc.d/rnsd restart 2>&1', $restartOut, $restartCode);
        if ($restartCode !== 0) {
            fprintf(STDERR, "[reconfigure] WARNING: rnsd restart returned %d\n", $restartCode);
        }
    } else {
        fprintf(STDERR, "[reconfigure] rnsd is disabled, stopping...\n");
        exec('/usr/local/etc/rc.d/rnsd stop 2>&1');
    }

    fprintf(STDERR, "[reconfigure] Done.\n");
}

/**
 * Minimal template renderer: replaces {{ var_name }} with values.
 */
function renderTemplate(string $template, array $vars): string
{
    return preg_replace_callback(
        '/\{\{\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*(?:\|\s*default\(([^)]*)\)\s*)?\}\}/',
        function (array $m) use ($vars): string {
            $key = $m[1];
            $default = $m[2] ?? '';
            // Support dot-notation
            $keys = explode('.', $key);
            $value = $vars;
            foreach ($keys as $k) {
                if (is_array($value) && isset($value[$k])) {
                    $value = $value[$k];
                } elseif (is_object($value) && isset($value->$k)) {
                    $value = $value->$k;
                } else {
                    return $default;
                }
            }
            return (string) $value;
        },
        $template
    );
}

main();

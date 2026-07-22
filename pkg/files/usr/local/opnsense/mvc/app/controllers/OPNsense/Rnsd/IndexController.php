<?php
/**
 * IndexController.php — Reticulum Bridge controller for OPNSense
 *
 * Serves the web UI page at /ui/rnsd/index
 * Part of the OPNSense MVC framework (Phalcon-based).
 */

namespace OPNsense\Rnsd;

class IndexController extends \OPNsense\Base\IndexController
{
    public function indexAction()
    {
        // Redirect to the general settings form
        $this->view->pick('OPNsense/Rnsd/index');
        $this->view->generalForm = $this->getForm("general");
    }
}

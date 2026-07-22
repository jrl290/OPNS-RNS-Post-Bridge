<?php
/**
 * General.php — OPNSense model for Reticulum Bridge settings
 *
 * Binds the form fields to the OPNSense config.xml backend.
 * Values are stored in:
 *   OPNsense.Rnsd.general.<field>
 */

namespace OPNsense\Rnsd;

class General extends \OPNsense\Base\BaseModel
{
    /**
     * Default values for all configurable fields.
     * These are used when the field is not present in config.xml.
     */
    public function __construct()
    {
        parent::__construct();

        $this->internalDefaults = [
            'enabled'                   => '0',
            'PostInterfaceNodeUrl'      => 'https://retichat.com/reticulum',
            'PostInterfaceWakeUrl'      => '',
            'PostInterfacePollInterval' => '5.0',
            'BackboneBindAddress'       => '0.0.0.0',
            'BackboneBindPort'          => '4242',
            'LogLevel'                  => '3',
            'MTU'                       => '500',
            'PathfinderMaxHops'         => '128',
            'EnableTransport'           => '1',
        ];
    }

    /**
     * Validation rules for form fields.
     */
    public function getNode_validators($node = null)
    {
        $validators = [];

        if ($node === null || $node === 'PostInterfaceNodeUrl') {
            $validators['PostInterfaceNodeUrl'] = [
                ['presence', ['message' => 'PostInterface Node URL is required']],
                ['url', ['message' => 'Must be a valid URL']],
            ];
        }

        if ($node === null || $node === 'BackboneBindPort') {
            $validators['BackboneBindPort'] = [
                ['presence', ['message' => 'Bind port is required']],
                ['integer', ['min' => 1, 'max' => 65535, 'message' => 'Port must be 1-65535']],
            ];
        }

        if ($node === null || $node === 'LogLevel') {
            $validators['LogLevel'] = [
                ['integer', ['min' => 0, 'max' => 7, 'message' => 'Log level 0-7']],
            ];
        }

        if ($node === null || $node === 'MTU') {
            $validators['MTU'] = [
                ['integer', ['min' => 100, 'max' => 65535, 'message' => 'MTU must be 100-65535']],
            ];
        }

        return $validators;
    }
}

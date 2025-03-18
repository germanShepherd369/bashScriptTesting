<?php

namespace Drupal\custom_footer\Plugin\Block;

use Drupal\Core\Block\BlockBase;

/**
 * Provides a 'Custom Footer Block'.
 *
 * @Block(
 *   id = "custom_footer_block",
 *   admin_label = @Translation("Custom Footer Block")
 * )
 */
class FooterBlock extends BlockBase {

  /**
   * {@inheritdoc}
   */
  public function build() {
    return [
      '#theme' => 'footer_block',
      '#attached' => [
        'library' => [
          'custom_footer/footer_styles',
        ],
      ],
    ];
  }

}

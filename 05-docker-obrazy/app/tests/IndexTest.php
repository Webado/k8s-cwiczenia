<?php

use PHPUnit\Framework\TestCase;

final class IndexTest extends TestCase
{
    public function testPhpVersion(): void
    {
        self::assertTrue(version_compare(PHP_VERSION, '8.3.0', '>='));
    }
}

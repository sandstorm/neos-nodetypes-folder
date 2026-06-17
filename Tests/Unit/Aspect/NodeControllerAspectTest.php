<?php

declare(strict_types=1);

namespace Sandstorm\NodeTypes\Folder\Tests\Unit\Aspect;

use Neos\Flow\Aop\Advice\AdviceChain;
use Neos\Flow\Aop\JoinPointInterface;
use Neos\Neos\FrontendRouting\Exception\InvalidShortcutException;
use Neos\Neos\FrontendRouting\Exception\NodeNotFoundException;
use PHPUnit\Framework\TestCase;
use Sandstorm\NodeTypes\Folder\Aspect\NodeControllerAspect;
use Sandstorm\NodeTypes\Folder\Exception\FolderDirectAccessException;

/**
 * @covers \Sandstorm\NodeTypes\Folder\Aspect\NodeControllerAspect
 *
 * @internal unit test for the AOP exception-conversion logic
 */
final class NodeControllerAspectTest extends TestCase
{
    private NodeControllerAspect $aspect;

    protected function setUp(): void
    {
        $this->aspect = new NodeControllerAspect();
    }

    /** @test */
    public function NodeNotFoundException_wrapping_InvalidShortcutException_is_converted_to_FolderDirectAccessException(): void
    {
        $joinPoint = $this->joinPointThrowing(
            new NodeNotFoundException('noTarget folder', 1430218730, new InvalidShortcutException())
        );

        $this->expectException(FolderDirectAccessException::class);
        $this->aspect->convertNoTargetFolderToNotFound($joinPoint);
    }

    /** @test */
    public function converted_FolderDirectAccessException_carries_statusCode_404(): void
    {
        $joinPoint = $this->joinPointThrowing(
            new NodeNotFoundException('noTarget folder', 1430218730, new InvalidShortcutException())
        );

        try {
            $this->aspect->convertNoTargetFolderToNotFound($joinPoint);
        } catch (FolderDirectAccessException $e) {
            self::assertSame(404, $e->getStatusCode());
            return;
        }

        $this->fail('Expected FolderDirectAccessException to be thrown');
    }

    /** @test */
    public function NodeNotFoundException_with_unrelated_previous_is_rethrown_unchanged(): void
    {
        $original = new NodeNotFoundException('unrelated node error', 0, new \RuntimeException('something else'));
        $joinPoint = $this->joinPointThrowing($original);

        try {
            $this->aspect->convertNoTargetFolderToNotFound($joinPoint);
        } catch (NodeNotFoundException $e) {
            self::assertSame($original, $e);
            return;
        }

        $this->fail('Expected original NodeNotFoundException to be rethrown');
    }

    /** @test */
    public function no_exception_passes_through_silently(): void
    {
        $this->expectNotToPerformAssertions();
        $this->aspect->convertNoTargetFolderToNotFound($this->silentJoinPoint());
    }

    // -------------------------------------------------------------------------

    private function joinPointThrowing(\Exception $exception): JoinPointInterface
    {
        $adviceChain = $this->createMock(AdviceChain::class);
        $adviceChain->method('proceed')->willThrowException($exception);

        $joinPoint = $this->createMock(JoinPointInterface::class);
        $joinPoint->method('getAdviceChain')->willReturn($adviceChain);

        return $joinPoint;
    }

    private function silentJoinPoint(): JoinPointInterface
    {
        $adviceChain = $this->createMock(AdviceChain::class);

        $joinPoint = $this->createMock(JoinPointInterface::class);
        $joinPoint->method('getAdviceChain')->willReturn($adviceChain);

        return $joinPoint;
    }
}

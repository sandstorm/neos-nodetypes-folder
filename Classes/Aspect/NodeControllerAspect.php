<?php

declare(strict_types=1);

namespace Sandstorm\NodeTypes\Folder\Aspect;

use Neos\Flow\Annotations as Flow;
use Neos\Flow\Aop\JoinPointInterface;
use Neos\Neos\FrontendRouting\Exception\InvalidShortcutException;
use Neos\Neos\FrontendRouting\Exception\NodeNotFoundException;
use Sandstorm\NodeTypes\Folder\Exception\FolderDirectAccessException;

/**
 * Converts the 500-typed NodeNotFoundException that NodeController throws for
 * "noTarget" shortcut folders into a 404-typed FolderDirectAccessException, so
 * Flow's notFoundExceptions rendering group produces an HTTP 404 instead of 500.
 *
 * @see NodeNotFoundException — caught when its $previous is InvalidShortcutException
 * @see FolderDirectAccessException — re-thrown with statusCode 404
 *
 * @api intercepts a Neos core public method to fix an unhandled edge case
 */
#[Flow\Aspect]
final class NodeControllerAspect
{
    /**
     * NodeController::showAction() catches InvalidShortcutException from
     * NodeShortcutResolver and wraps it in NodeNotFoundException (code 1430218730,
     * statusCode 500). This advice detects that specific wrapping and re-throws
     * as FolderDirectAccessException (statusCode 404).
     */
    #[Flow\Around('method(Neos\Neos\Controller\Frontend\NodeController->showAction())')]
    public function convertNoTargetFolderToNotFound(JoinPointInterface $joinPoint): void
    {
        try {
            $joinPoint->getAdviceChain()->proceed($joinPoint);
        } catch (NodeNotFoundException $e) {
            if ($e->getPrevious() instanceof InvalidShortcutException) {
                throw new FolderDirectAccessException($e->getMessage(), $e->getCode(), $e);
            }
            throw $e;
        }
    }
}

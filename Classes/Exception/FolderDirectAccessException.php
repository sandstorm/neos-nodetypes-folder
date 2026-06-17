<?php

declare(strict_types=1);

namespace Sandstorm\NodeTypes\Folder\Exception;

/**
 * Thrown when a folder node (targetMode "noTarget") is visited directly via its
 * URI segment. Signals HTTP 404 so Flow's error handler renders the site's
 * not-found page instead of a generic 500 error.
 *
 * @internal thrown exclusively by {@see NodeControllerAspect}
 */
final class FolderDirectAccessException extends \Neos\Flow\Exception
{
    protected $statusCode = 404;
}

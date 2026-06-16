<?php

/*
 * This file is part of the Sandstorm.NodeTypes.Folder package.
 */

use Behat\Behat\Context\Context as BehatContext;
use Neos\Behat\FlowBootstrapTrait;
use Neos\Behat\FlowEntitiesTrait;
use Neos\ContentRepository\Core\ContentRepository;
use Neos\ContentRepository\Core\Factory\ContentRepositoryServiceFactoryInterface;
use Neos\ContentRepository\Core\Factory\ContentRepositoryServiceInterface;
use Neos\ContentRepository\Core\SharedModel\ContentRepository\ContentRepositoryId;
use Neos\ContentRepository\TestSuite\Behavior\Features\Bootstrap\CRBehavioralTestsSubjectProvider;
use Neos\ContentRepository\TestSuite\Behavior\Features\Bootstrap\CRTestSuiteTrait;
use Neos\ContentRepository\TestSuite\Behavior\Features\Bootstrap\MigrationsTrait;
use Neos\ContentRepository\TestSuite\Fakes\FakeContentDimensionSourceFactory;
use Neos\ContentRepository\TestSuite\Fakes\FakeNodeTypeManagerFactory;
use Neos\ContentRepositoryRegistry\ContentRepositoryRegistry;
use Neos\Flow\Core\Bootstrap;
use Neos\Flow\Persistence\PersistenceManagerInterface;
use Neos\Flow\Tests\FunctionalTestRequestHandler;
use Neos\Flow\Utility\Environment;
use Neos\Http\Factories\ServerRequestFactory;
use Neos\Http\Factories\UriFactory;

// Pull upstream Neos.Neos test traits in by direct require — they live in the global
// namespace and Behat's autoload only handles one path per namespace. require_once
// is the simplest stable way to reuse them without duplicating the code.
$neosNeosBootstrap = __DIR__ . '/../../../../../../Application/Neos.Neos/Tests/Behavior/Features/Bootstrap';
require_once $neosNeosBootstrap . '/RoutingTrait.php';
require_once $neosNeosBootstrap . '/ExceptionsTrait.php';

class FeatureContext implements BehatContext
{
    use FlowBootstrapTrait;
    use FlowEntitiesTrait;

    use CRTestSuiteTrait;
    use CRBehavioralTestsSubjectProvider;
    use MigrationsTrait;
    use RoutingTrait;
    use ExceptionsTrait;
    use HttpJsonPostTrait;

    protected Environment $environment;

    protected ContentRepositoryRegistry $contentRepositoryRegistry;
    protected PersistenceManagerInterface $persistenceManager;

    public function __construct()
    {
        self::bootstrapFlow();
        $this->environment = $this->getObject(Environment::class);
        $this->contentRepositoryRegistry = $this->getObject(ContentRepositoryRegistry::class);
        $this->persistenceManager = $this->getObject(PersistenceManagerInterface::class);
    }

    /*
     * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
     *  Please don't add any generic step definitions here and use   *
     *  a dedicated trait instead to keep this main class tidied up. *
     * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
     */

    /**
     * @BeforeScenario
     */
    public function resetContentRepositoryComponents(): void
    {
        FakeContentDimensionSourceFactory::reset();
        FakeNodeTypeManagerFactory::reset();
    }

    /**
     * Activate a {@see FunctionalTestRequestHandler} so the upstream `RoutingTrait`
     * can invoke the real Flow router on `@When I am on URL …`. Inlined instead of
     * mixing in `BrowserTrait` to avoid pulling Neos.Neos.Ui's FeedbackCollection
     * into our test dependencies.
     *
     * @BeforeScenario
     */
    public function setupFunctionalTestRequestHandler(): void
    {
        $bootstrap = $this->getObject(Bootstrap::class);
        $requestHandler = new FunctionalTestRequestHandler($bootstrap);
        $request = (new ServerRequestFactory(new UriFactory()))
            ->createServerRequest('GET', 'http://localhost/flow/test');
        $requestHandler->setHttpRequest($request);
        $bootstrap->setActiveRequestHandler($requestHandler);
    }

    protected function getContentRepositoryService(
        ContentRepositoryServiceFactoryInterface $factory
    ): ContentRepositoryServiceInterface {
        return $this->contentRepositoryRegistry->buildService(
            $this->currentContentRepository->id,
            $factory
        );
    }

    protected function createContentRepository(
        ContentRepositoryId $contentRepositoryId
    ): ContentRepository {
        $this->contentRepositoryRegistry->resetFactoryInstance($contentRepositoryId);
        $contentRepository = $this->contentRepositoryRegistry->get($contentRepositoryId);
        FakeContentDimensionSourceFactory::reset();
        FakeNodeTypeManagerFactory::reset();

        return $contentRepository;
    }
}

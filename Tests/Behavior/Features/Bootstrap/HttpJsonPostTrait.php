<?php

declare(strict_types=1);

use Behat\Gherkin\Node\PyStringNode;
use Neos\Flow\Http\Client\Browser;
use Neos\Flow\Http\Client\InternalRequestEngine;
use PHPUnit\Framework\Assert;
use Psr\Http\Message\ResponseInterface;

/**
 * HTTP POST + JSON-response assertions for testing controller endpoints
 * end-to-end through the real Flow router (routes + policy + controller).
 *
 * @internal step definitions for behat scenarios that exercise HTTP endpoints.
 */
trait HttpJsonPostTrait
{
    /**
     * @template T of object
     * @param class-string<T> $className
     *
     * @return T
     */
    abstract private function getObject(string $className): object;

    private ?ResponseInterface $lastResponse = null;
    private ?string $lastResponseBody = null;

    /**
     * @When I POST JSON to URL :url:
     */
    public function iPostJsonToUrl(string $url, PyStringNode $jsonBody): void
    {
        $browser = new Browser();
        $browser->setRequestEngine($this->getObject(InternalRequestEngine::class));

        $this->lastResponse = $browser->request(
            $url,
            'POST',
            [],
            [],
            ['CONTENT_TYPE' => 'application/json'],
            $jsonBody->getRaw(),
        );
        $this->lastResponseBody = (string)$this->lastResponse->getBody();
    }

    /**
     * @Then the response status code should be :code
     */
    public function theResponseStatusCodeShouldBe(int $code): void
    {
        Assert::assertNotNull($this->lastResponse, 'No HTTP response captured');
        Assert::assertSame(
            $code,
            $this->lastResponse->getStatusCode(),
            'Response body was: ' . $this->lastResponseBody,
        );
    }

    /**
     * @Then the response JSON should equal:
     */
    public function theResponseJsonShouldEqual(PyStringNode $expected): void
    {
        Assert::assertNotNull($this->lastResponseBody, 'No HTTP response captured');
        $actual = json_decode($this->lastResponseBody, true, 512, JSON_THROW_ON_ERROR);
        $expectedDecoded = json_decode($expected->getRaw(), true, 512, JSON_THROW_ON_ERROR);
        Assert::assertEquals($expectedDecoded, $actual, 'Response body was: ' . $this->lastResponseBody);
    }

    /**
     * @Then the response JSON should contain key :key with value :value
     */
    public function theResponseJsonShouldContainKeyWithValue(string $key, string $value): void
    {
        Assert::assertNotNull($this->lastResponseBody, 'No HTTP response captured');
        $actual = json_decode($this->lastResponseBody, true, 512, JSON_THROW_ON_ERROR);
        $expectedValue = json_decode($value, true);
        Assert::assertArrayHasKey($key, $actual, 'Response body was: ' . $this->lastResponseBody);
        Assert::assertEquals(
            $expectedValue,
            $actual[$key],
            'Response body was: ' . $this->lastResponseBody,
        );
    }

    /**
     * Verifies that the first element of the "conflicts" array in the response
     * JSON contains the given key — used to assert the collision response shape.
     *
     * @Then the first conflict in the response JSON should contain key :key
     */
    public function theFirstConflictInResponseJsonShouldContainKey(string $key): void
    {
        Assert::assertNotNull($this->lastResponseBody, 'No HTTP response captured');
        $actual = json_decode($this->lastResponseBody, true, 512, JSON_THROW_ON_ERROR);
        Assert::assertArrayHasKey('conflicts', $actual, 'Response body was: ' . $this->lastResponseBody);
        Assert::assertNotEmpty($actual['conflicts'], 'conflicts array is empty; response body was: ' . $this->lastResponseBody);
        Assert::assertArrayHasKey($key, $actual['conflicts'][0], 'First conflict is missing key "' . $key . '"; response body was: ' . $this->lastResponseBody);
    }
}

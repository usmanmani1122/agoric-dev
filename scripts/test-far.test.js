import '@endo/init/debug.js';

import { Far, GET_METHOD_NAMES, PASS_STYLE } from '@endo/pass-style';
// eslint-disable-next-line import/no-unresolved
import test from 'ava';
import cryptoRandomString from 'crypto-random-string';

const farName = cryptoRandomString({ length: 8 });
const noop = () => {};
const randomString = cryptoRandomString({ length: 16, type: 'alphanumeric' });
const randomStringKey = cryptoRandomString({ length: 8 });

class TestClass {
  echo() {}
}

/**
 * @type {{[key: string]: typeof noop}}
 */
const ObjectWithNonValuePropertyDescriptor = {
  get [randomStringKey]() {
    return this.foo || noop;
  },
  /**
   * @param {typeof noop} foo
   */
  set [randomStringKey](foo) {
    this.foo = foo || noop;
  },
};

test("Shouldn't be able to convert a string", ({ throws }) =>
  throws(() => Far(farName, randomString), {
    message: `cannot serialize non-objects as Remotable "${randomString}"`,
  }));

test("Shouldn't be able to convert an array", ({ throws }) =>
  throws(() => Far(farName, [randomString]), {
    message: `cannot serialize arrays as Remotable ["${randomString}"]`,
  }));

test("Shouldn't be able to convert an object with non functional properties", ({
  throws,
}) =>
  throws(() => Far(farName, { [randomStringKey]: randomString }), {
    message: `cannot serialize Remotables with non-methods like "${randomStringKey}" in {"${randomStringKey}":"${randomString}"}`,
  }));

test("Shouldn't be able to convert an object with non value property descriptor", ({
  throws,
}) =>
  throws(() => Far(farName, ObjectWithNonValuePropertyDescriptor), {
    message: `cannot serialize Remotables with accessors like "${randomStringKey}" in {"${randomStringKey}":"[Function ${noop.name}]"}`,
  }));

test("Shouldn't be able to convert an object with a function with pass style property", ({
  throws,
}) => {
  const noopFunction = () => {};
  noopFunction[PASS_STYLE] = { value: randomString };
  throws(
    () =>
      Far(farName, {
        [randomStringKey]: noopFunction,
      }),
    {
      message: `cannot serialize Remotables with non-methods like "${randomStringKey}" in {"${randomStringKey}":"[Function ${noopFunction.name}]"}`,
    },
  );
});

test("Shouldn't be able to convert an object with an already existing PASS_STYLE symbol", ({
  throws,
}) =>
  throws(
    () =>
      Far(farName, {
        [randomStringKey]: noop,
        [PASS_STYLE]: noop,
      }),
    {
      message: `A pass-by-remote cannot shadow "[${PASS_STYLE.toString()}]"`,
    },
  ));

test("Shouldn't be able to convert a frozen object", ({ throws }) =>
  throws(
    () =>
      Far(
        farName,
        Object.freeze({
          [randomStringKey]: noop,
          [GET_METHOD_NAMES]: noop,
        }),
      ),
    {
      message: /^Remotable .* is already frozen$/,
    },
  ));

test("Shouldn't be able to convert a class instance", ({ throws }) =>
  throws(() => Far(farName, new TestClass()), {
    message: 'For now, remotables cannot inherit from anything unusual, in {}',
  }));

test(`Far object should have all keys names under ${GET_METHOD_NAMES} property`, ({
  true: isTrue,
}) =>
  isTrue(
    /** @type {Array<string>} */ (
      Far(farName, { [randomStringKey]: noop })[GET_METHOD_NAMES]()
    ).every((methodName) =>
      [GET_METHOD_NAMES, randomStringKey].includes(methodName),
    ),
  ));

test('Far object should not be mutable', ({ throws }) =>
  throws(
    () => (Far(farName, { [randomStringKey]: noop })[randomStringKey] = noop),
    {
      message: new RegExp(
        `^Cannot assign to read only property '${randomStringKey}'.*$`,
      ),
    },
  ));

test('Far object', ({ true: isTrue }) =>
  isTrue(
    !!Far(farName, { [randomStringKey]: noop })
      .toString()
      .match(new RegExp(`.*Alleged: ${farName}.*`)),
  ));

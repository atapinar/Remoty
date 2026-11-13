import java.lang.reflect.Method;

public class PQ {
    static final String[] ITEMS = {"brightness", "contrast", "saturation", "sharpness", "mode"};
    static final String[] NAMES = {"Brightness", "Contrast", "Saturation", "Sharpness", "PQMode"};
    static Object scm;

    static int call(String name, Object... args) throws Exception {
        Class<?>[] types = new Class<?>[args.length];
        for (int i = 0; i < args.length; i++) types[i] = int.class;
        Method m = scm.getClass().getMethod(name, types);
        return (Integer) m.invoke(scm, args);
    }

    static int index(String item) {
        for (int i = 0; i < ITEMS.length; i++) if (ITEMS[i].equals(item)) return i;
        throw new IllegalArgumentException("unknown item " + item);
    }

    static int get(String item) throws Exception {
        return call("Get" + NAMES[index(item)]);
    }

    static int set(String item, int value) throws Exception {
        String name = "Set" + NAMES[index(item)];
        if (item.equals("mode")) return call(name, value, 1, 0);
        if (value < 0 || value > 100) throw new IllegalArgumentException("value out of range");
        if (item.equals("sharpness")) return call(name, value, 1, 1);
        return call(name, value, 1);
    }

    public static void main(String[] args) {
        try {
            scm = Class.forName("com.droidlogic.app.SystemControlManager").getMethod("getInstance").invoke(null);
            if (args.length >= 1 && args[0].equals("get")) {
                String[] items = args.length > 1 ? new String[]{args[1]} : ITEMS;
                for (String item : items) System.out.println(item + "=" + get(item));
            } else if (args.length == 3 && args[0].equals("set")) {
                int rc = set(args[1], Integer.parseInt(args[2]));
                System.out.println(args[1] + "=" + get(args[1]) + " rc=" + rc);
            } else {
                System.out.println("error=usage: get [item] | set <item> <value>");
                System.exit(2);
            }
        } catch (Throwable t) {
            Throwable c = t.getCause() != null ? t.getCause() : t;
            System.out.println("error=" + c);
            System.exit(1);
        }
        System.exit(0);
    }
}
